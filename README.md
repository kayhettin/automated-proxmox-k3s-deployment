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
* `playbooks/01-build-template.yml`: Idempotent playbook that downloads the Rocky Linux 9 cloud image and converts it to a Proxmox template backed by the Synology NFS share[cite: 1].
* `playbooks/02-prep-nodes.yml`: Disables SWAP/Firewalld, configures SELinux, and sets kernel routing parameters[cite: 1].
* `playbooks/03-install-k3s.yml`: Bootstraps the HA embedded etcd control plane, joins workers, and fetches the `kubeconfig`[cite: 1].

## Deployment Instructions
1. **Environment Setup:** Copy `.env.example` to `.env` and populate it with your specific SSH public key and a securely generated `K3S_TOKEN`.
2. **Network Initialization:** Run `scripts/01-setup-openwrt.sh` on your OpenWrt gateway to establish DHCP boundaries and VLAN definitions.
3. **Key Distribution:** Execute `scripts/02-push-keys.sh` from your Ansible node to distribute the Ed25519 key to the bare-metal Proxmox hosts. 
4. **Golden Image Creation:** Run `ansible-playbook playbooks/01-build-template.yml` to generate the Rocky 9 base template (VM ID `9000`) on Proxmox[cite: 1].
5. **Node Cloning:** Manually full-clone VM `9000` six times in Proxmox. Distribute the clones sequentially across your physical hypervisors to avoid NFS saturation[cite: 1]. Use the Cloud-Init tab to assign static IPs (`10.10.0.21` - `10.10.0.26`), regenerate the image, and boot[cite: 1].
6. **OS Preparation:** Run `ansible-playbook playbooks/02-prep-nodes.yml` to configure the kernel and security layers on the new clones.
7. **Cluster Deployment:** Run `ansible-playbook playbooks/03-install-k3s.yml` to form the cluster and retrieve credentials.

## Validation & Smoke Testing
Run the following checks from your Ansible control node to verify deployment success:

**1. Proxmox Quorum Validation:**
```bash
ssh root@10.10.0.11 "pvecm status"
