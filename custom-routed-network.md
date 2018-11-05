# Custom routed network

## sources from here

```txt
https://jamielinux.com/docs/libvirt-networking-handbook/custom-routed-network.html

# kvm durchleiten
https://forum.ubuntuusers.de/topic/kvm-gast-durchleiten-und-beschraenken/
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
CUSTOM_BRIDGE_NAME="virbr10-dummy"
sudo ip link add $CUSTOM_BRIDGE_NAME address $VIRBR10_DUMMY_MAC type dummy
ip addr show $CUSTOM_BRIDGE_NAME
```

## create bridge

```bash
brctl addbr virbr10
brctl stp virbr10 on
brctl addif virbr10 virbr10-dummy
ip address add 203.0.113.88/29 dev virbr10 broadcast 203.0.113.95
ip address add 2001:db8:aa::/64 dev virbr10
```



