#!/bin/bash
set -euo pipefail

echo "Configuring OpenWrt Network via UCI..."

# 1. Define the Lab Interface and IP
uci set network.lab=interface
uci set network.lab.proto='static'
uci set network.lab.device='br-lan.10'
uci set network.lab.ipaddr='10.10.0.1'
uci set network.lab.netmask='255.255.255.0'

# 2. Map Physical Ports to the VLAN (DSA Switching)
uci add network bridge-vlan || true
uci set network.@bridge-vlan[-1].device='br-lan'
uci set network.@bridge-vlan[-1].vlan='10'
uci add_list network.@bridge-vlan[-1].ports='lan1:u'
uci add_list network.@bridge-vlan[-1].ports='lan2:u'

# 3. Establish the DHCP Pool
uci set dhcp.lab=dhcp
uci set dhcp.lab.interface='lab'
uci set dhcp.lab.start='100'
uci set dhcp.lab.limit='150'
uci set dhcp.lab.leasetime='24h'

# 4. Enable Firewall Routing
# Attaches lab interface to the default lan firewall zone
uci add_list firewall.@zone[0].network='lab'

# 5. Commit and Apply
uci commit network
uci commit dhcp
uci commit firewall

/etc/init.d/network restart
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart

echo "OpenWrt Configuration Applied Successfully."
