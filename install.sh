#!/bin/bash

if [ -z  $RANCHER_STEP ];then
  export RANCHER_STEP=0
  echo $RANCHER_STEP
else
  echo $RANCHER_STEP
fi 

set -eu
source init.ini

# install expect
if [ $(command -v expect | wc -l) -eq 0 ];then
yum install -y expect
fi

function configSSH() {
  ip=$1
  user=$2
  password=$3

  expect <<EOF
set timeout 30
spawn ssh-copy-id ${user}@${ip}
expect {
        "(yes/no)" {
                send_user "enter yes\n"
                send "yes\r";
                exp_continue;
        }
        "*password:" {
                send_user "enter password:${password}\n";
                send "${password}\r";
		exp_continue;
        }
	timeout {
                send_user "connection to ${ip} timed out\n"
                exit
        }
	eof {
                send_user "exit!\r\n"
		exit
	}
}
EOF
}

echo "----10%----init env!"

if [ $RANCHER_STEP -le 0 ];then

if [ ! -e "$HOME/.ssh/id_rsa" ];then
expect -c "
spawn ssh-keygen -t rsa -b 4096
expect \"Enter file in which to save the key (/root/.ssh/id_rsa):\"
send \"\r\"
expect \"Enter passphrase (empty for no passphrase):\"
send \"\r\" 
expect \"Enter same passphrase again:\"
send \"\r\"
expect eof
"
fi

export RANCHER_STEP=1
fi

if [ $RANCHER_STEP -le 1 ];then
 
echo "----20%----config current node." 
hostname=master
cp ./tools/kubectl /usr/local/bin
cp ./tools/helm /usr/local/bin
cp ./config/daemon.json /tmp
./node_config.sh $hostname $k8s_user $k8s_passwd $master_node
configSSH localhost $k8s_user $k8s_passwd
curl -O http://192.168.8.8:8099/Rancher/images/registry-image.tar
docker load -i ./registry-image.tar
curl -O http://192.168.8.8:8099/Rancher/images/registry-rke-rancher-images.tar.gz
tar -zxvf ./registry-rke-rancher-images.tar.gz  -C  /
rm -rf ./registry-image.tar 
rm -rf ./registry-rke-rancher-images.tar.gz

REGISTRY_CONTAINERID=$(docker ps -aqf "name=registry")

if [ -n "$REGISTRY_CONTAINERID" ]; then

  docker rm -f $(docker stop $REGISTRY_CONTAINERID) 

fi

docker run -p 5000:5000  --restart=always --name registry -v /registry/:/var/lib/registry -d registry
export RANCHER_STEP=2

fi

if [ $RANCHER_STEP -le 2 ];then


echo "----50%----config other nodes."
nodesIP=($(echo $worker_nodes | sed -e 's/,/ /g'))
for index in ${!nodesIP[@]} 
do
  
  hostname=worker$((index+1))
  nodeIP=${nodesIP[$index]}
  configSSH $nodeIP $root_user $root_passwd
  scp ./node_config.sh $root_user@${nodeIP}:/tmp
  scp ./tools/kubectl $root_user@${nodeIP}:/usr/local/bin
  scp ./tools/helm $root_user@${nodeIP}:/usr/local/bin
  scp ./config/daemon.json $root_user@${nodeIP}:/tmp
  ssh $root_user@${nodeIP} "/tmp/node_config.sh $hostname $k8s_user $k8s_passwd $master_node"
  configSSH $nodeIP $k8s_user $k8s_passwd
done
export RANCHER_STEP=3

fi

if [ $RANCHER_STEP -le 3 ];then

echo "----60%----config rancher cluster."
./rancher-cluster/config-cluster.sh $master_node $worker_nodes
./tools/rke up --config ./rancher_cluster.yml

cp ./kube_config_rancher_cluster.yml  ~/.kube/config

nodesIP=($(echo $worker_nodes | sed -e 's/,/ /g'))
for index in ${!nodesIP[@]}
do
   nodeIP=${nodesIP[$index]}
   scp ./kube_config_rancher_cluster.yml $root_user@${nodeIP}:/root/.kube/config
done

export RANCHER_STEP=4

fi

if [ $RANCHER_STEP -le 4 ];then

echo  "----60%----install rancher 2.6.2"

./configure_rancher_server.sh  $admin_password  $master_node  $cluster_name
sleep 30
export RANCHER_STEP=5

fi

if [ $RANCHER_STEP -le 5 ];then

echo "----80%----install apps"

./install-apps/install_apps.sh

echo "----100%----successd."

fi


