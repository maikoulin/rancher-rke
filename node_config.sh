#!/bin/bash
set -eu

hostname=${1}
user=${2-rke}
passwd=${3-dcncloud}
master_node=${4}

# update to newest version
version=$(cat /etc/system-release | awk '{print $4}')
if [ $version \< "7.7" ];then
    sudo yum clean all
    sudo yum update -y
fi

# disable firewall and selinux
systemctl  stop firewalld.service
systemctl  disable  firewalld.service >> /dev/null 2>&1
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0 || true

# disable swap
if [ $(swapon -s | wc -l) -gt 0 ];then
swapoff /dev/dm-1
sed -i 's/^\([\/a-zA-Z\\-]\+\)\s\+swap\s\+\(.*\)/#\0/' /etc/fstab
echo 0 > /proc/sys/vm/swappiness
echo "vm.swappiness=0" >> /etc/sysctl.conf
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
fi

if [ $(command -v docker|wc -l) -eq 0 ];then
sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine
sudo yum install -y yum-utils  net-tools
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce-20.10.12 docker-ce-cli-20.10.12 containerd.io
sudo systemctl start docker
sudo systemctl enable docker

sudo groupadd docker || true
fi

# install expect
if [ $(command -v expect | wc -l) -eq 0 ];then
yum install -y expect
fi

# install vim
if [ $(command -v vim | wc -l) -eq 0 ];then
yum install -y vim
fi

# add user
if [ $(grep "^${user}:" /etc/passwd | wc -l) -eq 0 ];then
useradd -d /home/${user} -m $user
expect -c "
spawn passwd $user
expect \"Changing password for user $user.*\nNew password:\"
send \"${passwd}\r\"
expect \"Retype new password:\"
send \"${passwd}\r\"
expect eof
"
usermod -aG docker $user
##newgrp docker

hostnamectl set-hostname $hostname
fi

if [ $(grep "^.\?AllowTcpForwarding" /etc/ssh/sshd_config | wc -l) -gt 0 ];then
sed -i 's/^.\?AllowTcpForwarding.*/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
else
echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
fi

#ip l s eth0 mtu 1400
ifconfig eth0 mtu 1400


#mkdir kube file
mkdir -p /root/.kube

#config docker insecure-registries
echo "${master_node}     hub.local"  >> /etc/hosts
cp /tmp/daemon.json /etc/docker
systemctl daemon-reload
systemctl restart docker


