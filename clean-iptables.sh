sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X

sudo iptables  -L -n -v --line-numbers
sudo iptables -t nat -L -n -v --line-numbers
sudo iptables -t mangle -L -n -v --line-numbers

