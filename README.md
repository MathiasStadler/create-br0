# crate-br0

## copy and paste

```bash
sudo ip link add br0 type bridge
# forward_delay 0 can also be specified here
sudo ip link set br0 type bridge forward_delay 0
echo "0" | sudo tee --append /sys/class/net/br0/bridge/stp_state
sudo ip link set br0 up
sudo  ip link set enp0s25 master br0


sudo ip link set enp0s25 nomaster
sudo ip link set br0 down
sudo ip link delete br0 type bridge
```

## with help of command netctl start bridge

```bash
sudo cp /etc/netctl/examples/bridge /etc/netctl/bridge
sudo vim /etc/netctl/bridge
# set your real phy network interface
BindsToInterfaces=(enp0s25)
# save file 
# start bridge
sudo netctl start bridge
# check with command
ip show addr # ip addr has change
# make our bridge start on boot
sudo netctl enable bridge
```

## networks settings via /etc/sysctl/

```bash
cat /etc/sysctl.d/99-sysctl.conf
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
net.ipv4.ip_forward = 1

# activate w/o reboot
sudo sysctl --system 

```

## source

```txt
https://fedoramagazine.org/build-network-bridge-fedora/
https://www.lindberg.io/2015/06/10/bridge-interface-in-arch-linux/
```


## libvirt network

```bash
sudo virsh net-list --all

# delete network
sudo virsh net-undefine vagrant-libvirt

# start network
sudo virsh net-start default 
```