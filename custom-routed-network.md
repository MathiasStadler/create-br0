# Custom routed network

## sources from here

```txt
# youtube bridge
https://www.youtube.com/watch?v=XivXeKxQ4KI

#
https://jamielinux.com/docs/libvirt-networking-handbook/custom-routed-network.html


# kvm durchleiten
https://forum.ubuntuusers.de/topic/kvm-gast-durchleiten-und-beschraenken/

# dnsmasq on arch
https://www.ask-sheldon.com/run-dnsmasq-as-a-local-dns-server-arch-linux/


# create dnsmasq@virbr10.service
https://jamielinux.com/docs/libvirt-networking-handbook/appendix/run-dnsmasq-with-systemd.html


# dnsmasq advance
https://www.linux.com/learn/intro-to-linux/2018/2/advanced-dnsmasq-tips-and-tricks

# tutorial bridge error
http://www.microhowto.info/troubleshooting/troubleshooting_ethernet_bridging_on_linux.html

# bridge tutorial
https://backreference.org/2010/03/26/tuntap-interface-tutorial/

# vm network bridge
https://vincent.bernat.ch/en/blog/2017-linux-bridge-isolation

# iptables explanation deutsche
https://www.karlrupp.net/de/computer/nat_tutorial

```
## show all network

```bash
sudo virsh net-list --all
```


## create random mac

- Choose a MAC address for the virtual bridge. Use hexdump to generate a random MAC address in the format that libvirt expects (52:54:00:xx:xx:xx for KVM, 00:16:3e:xx:xx:xx for Xen).

```bash
VIRBR10_DUMMY_MAC=$(hexdump -vn3 -e '/3 "52:54:00"' -e '/1 ":%02x"' -e '"\n"' /dev/urandom)
echo $VIRBR10_DUMMY_MAC
```

## check kernel module

- TODO: scripting missing

```bash
lsmod |grep dummy
# if not load

# load
sudo modprobe dummy

# persistent Module loading
echo "dummy" | sudo tee /etc/modules-load.d/dummy.conf
```

## create interface

```bash
CUSTOM_BRIDGE_INTERFACE_NAME="virbr10-net"
sudo ip link add $CUSTOM_BRIDGE_INTERFACE_NAME address $VIRBR10_DUMMY_MAC type dummy
# set interace to listening or forwarding. Forwarding only if the kernel module ip_gre is loaded
# ‘listening’ indicates that the STP implementation has not yet decided whether the port should enter the ‘forwarding’ or ‘blocked’ state
# disabled’ indicates that the port is non-operational for some other reason
sudo modprobe ip_gre
sudo ip link set $CUSTOM_BRIDGE_INTERFACE_NAME up
ip addr show $CUSTOM_BRIDGE_INTERFACE_NAME
```

## stop and delete bridge

```bash
# stop bridge
sudo ip link set dev virbr10 down
# delete bridge
sudo brctl delbr virbr10
```

## create bridge

```bash
CUSTOM_BRIDGE_NAME="virbr10"
sudo brctl addbr $CUSTOM_BRIDGE_NAME
sudo brctl stp $CUSTOM_BRIDGE_NAME on
sudo brctl addif $CUSTOM_BRIDGE_NAME $CUSTOM_BRIDGE_INTERFACE_NAME
sudo ip address add 203.0.113.1/24 dev $CUSTOM_BRIDGE_NAME broadcast 203.0.113.255
# sudo ip address add 2001:db8:aa::/64 dev virbr10
sudo ip link set dev $CUSTOM_BRIDGE_NAME up
sudo ip addr show $CUSTOM_BRIDGE_NAME
```

## disable default network

```bash
# list network
sudo virsh net-list --all

# network if NOT active 
sudo virsh net-start default

# destroy
sudo virsh net-destroy default

# disable autostart
sudo virsh net-autostart --disable default
```

## networks settings via /etc/sysctl/

```bash
SYSCTL_CUSTOM_CONF_FILE="/etc/sysctl.d/99-sysctl.conf"
cat << EOF | sudo tee -a $SYSCTL_CUSTOM_CONF_FILE
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
EOF
# delete double lines
sort -u $SYSCTL_CUSTOM_CONF_FILE | sudo tee $SYSCTL_CUSTOM_CONF_FILE
# activate w/o reboot
sudo sysctl --system

# check settings activate
sudo sysctl -a |grep -E 'nf-call|net.ipv4.ip_forward|conf.all.forwarding'

```

## config iptables

- edit /etc/iptables/iptables.rules
- this script will used by iptabbles.services
- this ensure that the firewall rules are activated every time you restart
- cat /usr/lib/systemd/system/iptables.service

```bash
# Allow inbound traffic to the private subnet.
-A FORWARD -d 203.0.113.88/29 -o virbr10 -j ACCEPT
# Allow outbound traffic from the private subnet.
-A FORWARD -s 203.0.113.88/29 -i virbr10 -j ACCEPT
# Allow traffic between virtual machines.
-A FORWARD -i virbr10 -o virbr10 -j ACCEPT
# Reject everything else.
-A FORWARD -i virbr10 -j REJECT --reject-with icmp-port-unreachable
-A FORWARD -o virbr10 -j REJECT --reject-with icmp-port-unreachable
```

## reload your iptables config

**double check** your config before you make this step

```bash
# reload
>sudo iptables-restore </etc/iptables/iptables.rules
# check
> sudo iptables -nL
```

## iptables for dnsmasq

```bash

# delete COMMIT end of line
sed -i '/COMMIT/d' /etc/iptables/iptables.rules

cat << EOF | sudo tee -a /etc/iptables/iptables.rules
# Accept DNS (port 53) and DHCP (port 67) packets from VMs.
-A INPUT -i virbr10 -p udp -m udp -m multiport --dports 53,67 -j ACCEPT
-A INPUT -i virbr10 -p tcp -m tcp -m multiport --dports 53,67 -j ACCEPT

# If using DHCPv6 instead of SLAAC, also allow UDP port 547.
# -A INPUT -i virbr10 -p udp -m udp --dport 547 -j ACCEPT

COMMIT
EOF
```

## reload your iptables config ( for dnsmasq )

**double check** your config before you make this step

```bash
# reload
>sudo iptables-restore </etc/iptables/iptables.rules
# check
> sudo iptables -nL
```

## Configuration of dnsmasq@<bridge>.service

```bash
# create configuration folder
sudo mkdir /etc/dnsmasq.d

# enable loads all configuration files in /etc/dnsmasq.d except *.bak files
echo 'conf-dir=/etc/dnsmasq.d,.bak' |sudo tee -a /etc/dnsmasq.conf

# create directory for instance files
sudo mkdir -p /var/lib/dnsmasq/virbr10

# create host file
sudo touch /var/lib/dnsmasq/virbr10/hostsfile

# create leases file
sudo touch /var/lib/dnsmasq/virbr10/leases

# create dnsmasq network configuration
cat << EOF | sudo tee -a /var/lib/dnsmasq/virbr10/dnsmasq.conf
# Only bind to the virtual bridge. This avoids conflicts with other running
# dnsmasq instances.
except-interface=lo
bind-dynamic
interface=virbr10

# If using dnsmasq 2.62 or older, remove "bind-dynamic" and "interface" lines
# and uncomment these lines instead:
#bind-interfaces
#listen-address=203.0.113.88
#listen-address=2001:db8:aa::1

# IPv4 addresses to offer to VMs. This should match the chosen subnet.
dhcp-range=203.0.113.20,203.0.113.200

# Set this to at least the total number of addresses in DHCP-enabled subnets.
dhcp-lease-max=1000

# Assign IPv6 addresses via stateless address autoconfiguration (SLAAC).
# dhcp-range=2001:db8:aa::,ra-only

# Assign IPv6 addresses via DHCPv6 instead (requires dnsmasq 2.64 or later).
# Remember to allow all incoming UDP port 546 traffic on the VM.
#dhcp-range=2001:db8:aa::1000,2001:db8:aa::1fff
#enable-ra
#dhcp-lease-max=5000

# File to write DHCP lease information to.
dhcp-leasefile=/var/lib/dnsmasq/virbr10/leases
# File to read DHCP host information from.
dhcp-hostsfile=/var/lib/dnsmasq/virbr10/hostsfile
# Avoid problems with old or broken clients.
dhcp-no-override
# https://www.redhat.com/archives/libvir-list/2010-March/msg00038.html
strict-order
EOF
```

## check dnsmasq syntax

```bash
dnsmasq --test
```

## check dns

```bash
dig debian.org @203.0.113.1
```

## check DHCP

```bash
sudo dhcpcd -T virbr10
```

## prepare NetworkManager

```bash
NETWORK_MANAGER_DISPATCHER_SCRIPT="/etc/NetworkManager/dispatcher.d/99-virbr10"

cat << EOF | sudo tee -a $NETWORK_MANAGER_DISPATCHER_SCRIPT
#!/bin/sh
# See the "DISPATCHER SCRIPTS" section of `man NetworkManager`.
# Remember to make this file executable!
[ "$1" != "virbr10" ] && exit 0
case "$2" in
    "up")
        /bin/systemctl start dnsmasq@virbr10.service || :
        ;;
    "down")
        /bin/systemctl stop dnsmasq@virbr10.service || :
        ;;
esac
EOF

sudo chmod +x $NETWORK_MANAGER_DISPATCHER_SCRIPT
```

## create systemctl file

- from here
- https://jamielinux.com/docs/libvirt-networking-handbook/appendix/run-dnsmasq-with-systemd.html

```bash
cat << EOF | sudo tee -a /etc/systemd/system/dnsmasq@.service
# '%i' becomes 'virbr10' when running `systemctl start dnsmasq@virbr10.service`
# Remember to run `systemctl daemon-reload` after creating or editing this file.

[Unit]
Description=DHCP and DNS caching server for %i.
After=network.target

[Service]
ExecStart=/usr/sbin/dnsmasq -k --conf-file=/var/lib/dnsmasq/%i/dnsmasq.conf
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

## enable and start dnsmasq@<bridge>.services

```bash
sudo systemctl enable dnsmasq@virbr10.service
sudo systemctl start dnsmasq@virbr10.service
```

## systemctl list running services

```bash
sudo systemctl -t service
```
## dnsmasq start manual

```bash
sudo /usr/sbin/dnsmasq -k --conf-file=/var/lib/dnsmasq/virbr10/dnsmasq.conf --no-daemon --log-queries
```

## If you are running a system-wide instance of dnsmasq, you may need to configure it to ignore the virtual bridge

```bash
sudo rm -rf /etc/dnsmasq.d/virbr10.conf
echo "except-interface=virbr10" |sudo tee -a  /etc/dnsmasq.d/virbr10.conf
echo "bind-interfaces" | sudo tee -a  /etc/dnsmasq.d/virbr10.conf
sudo systemctl reenable NetworkManager
sudo systemctl restart NetworkManager
```

https://libvirt.org/sources/virshcmdref/html/sect-net-create.html

```xml
<network>
  <name>examplenetwork</name>
  <uuid>97ce3914-231e-4026-0a78-822e1e2e7226</uuid>
  <forward mode='route'/>
  <bridge name='virbr10' stp='on' delay='0' />
  <ip address='203.0.113.88' netmask='255.255.255.0'>
  </ip>
</network>
```

```xml
<network>
    <name>examplenetwork</name>
    <forward mode='route'/>
    <bridge name='virbr10' stp='on' delay='0' />
    <ip address='203.0.113.1' netmask='255.255.255.0'>
        <dhcp>
        <range start='203.0.113.40' end='203.0.113.200' />
        </dhcp>
    </ip>
</network>
```

```xml
<network>
  <name>examplenetwork</name>
  <forward mode='route'/>
  <bridge name='virbr10' stp='on' delay='0'/>
  <dns>
  <txt name="example" value="example value"/>
  <forwarder addr="8.8.8.8"/>
  </dns>
  <ip address='203.0.113.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='203.0.113.40' end='203.0.113.200'/>
    </dhcp>
  </ip>
</network>
```

```xml
<network>
    <name>examplenetwork</name>
    <forward mode='bridge'/>
    <bridge name='virbr10'/>
</network>
```

```bash
Description="virbr10 Bridge connection"
Interface=virbr10
Connection=bridge
BindsToInterfaces=(virbr10-net)
P=static
Address='203.0.113.1/24'
Gateway='203.0.113.1'
DNS='203.0.113.1'
## Ignore (R)STP and immediately activate the bridge
SkipForwardingDelay=yes
```

## arch netctl bridge

```txt
https://wiki.archlinux.org/index.php/Bridge_with_netctl
```

```bash
net-create /root/examplenetwork.xml
```

https://kashyapc.fedorapeople.org/virt/create-a-new-libvirt-bridge.txt



## virsh net overview

```txt
https://avdv.github.io/libvirt/formatnetwork.html
```

sudo ip -4 route add 203.0.113.0/24 via 192.168.178.101

sudo ip route del 203.0.113.0/24


## set default route 

```bash
sudo ip route add default via 203.0.113.1
```

## net

```bash
sudo ip -4 route add 203.0.113.0/24 dev virbr10


sudo ip -4 route add 203.0.113.0/24 via 192.168.178.101 dev virbr10
```

## show interfaces state

```bash
brctl showstp virbr10
```

## show ebtables status

```bash
sudo ebtables -t filter -L
sudo ebtables -t nat -L
sudo ebtables -t broute -L
```

sudo sysctl -w net.ipv4.conf.all.proxy_arp=1

## masquerade to internet
https://serverfault.com/questions/845923/bridge-interface-for-kvm-vms-with-access-to-internet
sudo iptables --table nat --append POSTROUTING --out-interface enp0s25 -j MASQUERADE
sudo iptables --insert FORWARD --in-interface virbr10 -j ACCEPT

