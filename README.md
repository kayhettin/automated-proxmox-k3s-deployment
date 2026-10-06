# Enterprise Bare-Metal K8s Home Lab

## Architecture & Objective Overview
This repository provisions a Highly Available (HA) Kubernetes (K3s) cluster distributed across a 6-node Proxmox Virtual Environment on Rocky Linux 9. The architecture adheres to enterprise GitOps principles, utilizing a flat `/24` logically segmented network managed by a GL.iNet Flint 4 OpenWrt router, with local DNS resolved by a dedicated Pi-hole/Unbound tier. Synology NFS acts as the centralized storage backend, enabling Proxmox live migrations and persistent volume provisioning. Default K3s networking components are explicitly disabled to allow for eBPF routing (Cilium), L2 load balancing (MetalLB), and enterprise ingress (NGINX).

## Prerequisites
* **Network:** A `10.10.0.0/24` subnet. Gateway is `10.10.0.1`.
* **Hypervisor:** 6 physical nodes running Proxmox VE 8.x (`10.10.0.11` through `10.10.0.16`).
* **Storage:** Synology NAS (`10.10.0.60`) with an NFS share mapped to the Proxmox Datacenter as `kayology-vms`. 
* **Automation Node:** Ansible installed on a dedicated control machine (e.g., Raspberry Pi at `10.10.0.2`).
* **Keys:** An Ed25519 SSH keypair generated on the control node for passwordless execution.

## Directory/File Manifest
* `inventory/hosts.ini`: Ansible target matrix defining IPs and roles for the Proxmox and K3s tiers.
* `ansible.cfg`: Disables strict host key checking to prevent stalls on newly provisioned VMs.
* `scripts/01-setup-openwrt.sh`: Defines the flat network, DHCP scopes, and firewall zones on the routing layer.
* `scripts/02-push-keys.sh`: Automates distribution of the public SSH key to all physical and virtual nodes.
* `playbooks/01-build-template.yml`: Idempotent playbook that downloads the Rocky Linux 9 cloud image and converts it to a Proxmox template backed by the Synology NFS share.
* `playbooks/02-prep-nodes.yml`: Disables SWAP/Firewalld, configures SELinux, and sets kernel routing parameters.
* `playbooks/03-install-k3s.yml`: Bootstraps the HA embedded etcd control plane, joins workers, and fetches the `kubeconfig`.

## Deployment Instructions
1. **Environment Setup:** Copy `.env.example` to `.env` and populate it with your specific SSH public key and a securely generated `K3S_TOKEN`.
2. **Network Initialization:** Run `scripts/01-setup-openwrt.sh` on your OpenWrt gateway to establish DHCP boundaries and VLAN definitions.
3. **Key Distribution:** Execute `scripts/02-push-keys.sh` from your Ansible node to distribute the Ed25519 key to the bare-metal Proxmox hosts. 
4. **Golden Image Creation:** Run `ansible-playbook playbooks/01-build-template.yml` to generate the Rocky 9 base template (VM ID `9000`) on Proxmox.
5. **Node Cloning:** Manually full-clone VM `9000` six times in Proxmox. Distribute the clones sequentially across your physical hypervisors to avoid NFS saturation. Use the Cloud-Init tab to assign static IPs (`10.10.0.21` - `10.10.0.26`), regenerate the image, and boot.
6. **OS Preparation:** Run `ansible-playbook playbooks/02-prep-nodes.yml` to configure the kernel and security layers on the new clones.
7. **Cluster Deployment:** Run `ansible-playbook playbooks/03-install-k3s.yml` to form the cluster and retrieve credentials.

## Validation & Smoke Testing
Run the following checks from your Ansible control node to verify deployment success:

**1. Proxmox Quorum Validation:**
```bash
ssh root@10.10.0.11 "pvecm status"
```
## Troubleshooting / Common Pitfalls

*   **etcd I/O Degradation:** Kubernetes `etcd` is highly sensitive to disk write latency. If the backend Synology NFS storage experiences high latency or you attempt to run `etcd` on slow mechanical drives, the cluster will experience timeouts and leader-election thrashing. Use high-quality SSDs and ensure disk latency is under 10ms.
*   **Proxmox Quorum Loss (Split-Brain):** A 6-node Proxmox cluster lacks a natural tie-breaker. If the network splits 3-v-3, the cluster loses quorum and locks into read-only mode to prevent data corruption. Always ensure the Raspberry Pi Corosync QDevice is active to provide the 7th tie-breaking vote.
*   **Synology NAS VM Disk Corruption:** When configuring the `proxmox-vms` NFS share on the Synology NAS, enabling "Data Checksums" or "Shared Folder Quotas" will cripple the cluster. VM disk files (`.raw`/`.qcow2`) generate continuous random I/O; checksums cause severe write amplification and CPU spikes, while quotas hide storage limits from Proxmox, resulting in catastrophic I/O errors. Leave these settings unchecked.
*   **Simultaneous NFS Cloning Lockups:** Rapidly cloning multiple VMs simultaneously to the Synology NFS backend can saturate the I/O pipeline, causing the cloning tasks to time out and lock the VMs. If this occurs, kill the frozen tasks, unlock the VMs via the Proxmox shell (`qm unlock <VMID>`), destroy the corrupted clones (`qm destroy <VMID>`), and recreate them sequentially.
*   **Proxmox NFS Template Error (`chattr` failure):** When executing the template conversion playbook, Proxmox will throw a `/usr/bin/chattr: Operation not supported` error. The NFS protocol does not support passing Linux extended file attributes over the network. The template conversion still succeeds; the Ansible playbook safely ignores this specific stderr output.
*   **Stale SSH Host Keys (Man-in-the-Middle warning):** Because IP addresses are reused in the lab, destroying and re-cloning a VM generates a new SSH host key, causing Ansible to reject the connection with a `REMOTE HOST IDENTIFICATION HAS CHANGED` error. Rely on the `ansible.cfg` configuration in this repository to bypass strict checking, or manually purge old keys using `ssh-keygen -R "10.10.0.x"`.
*   **Missing `firewalld` Service Failure:** Rocky Linux 9 Generic Cloud images do not ship with `firewalld` installed by default. Standard Ansible tasks designed to disable the service will crash. The node preparation playbook uses `ignore_errors: yes` for this task to bypass the failure cleanly.
*   **CPU Architecture Taints & Hardware Passthrough:** Mixing Intel and AMD processors in the worker nodes means hardware-specific workloads can fail if scheduled on the wrong node. Use Kubernetes `nodeSelectors` to pin pods requiring Intel QuickSync (like Jellyfin) strictly to the HP EliteDesk VMs where the iGPU is passed through via PCIe.
*   **Split-Brain DNS & Hairpin NAT:** If you expose services externally via the router, internal clients may fail to reach them if the router blocks hairpin NAT (NAT Loopback). Utilize the dedicated Pi-hole to map your public domain directly to the internal MetalLB Ingress IPs.
*   **The GitOps "Chicken and Egg" Lockout:** If ArgoCD manages the entire cluster state, an Ingress controller failure or ArgoCD crash can lock you out of the management UI. Always keep raw ArgoCD bootstrap manifests available in the Ansible control node, and rely on `kubectl port-forward` or the WireGuard VPN for emergency break-glass access.
