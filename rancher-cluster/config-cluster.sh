#!/bin/bash
set -eu

master_node=${1}
worker_nodes=${2}

rm -rf rancher_cluster.yml
cp ./rancher-cluster/nodes rancher_cluster.yml
eval sed 's/master_address/${master_node}/g' ./rancher-cluster/master >master_tmp
sed -i 's/master_hostname/master/g' master_tmp
paste master_tmp  >> rancher_cluster.yml
rm -rf master_tmp

nodesIP=($(echo $worker_nodes | sed -e 's/,/ /g'))
for index in ${!nodesIP[@]}
do
  
  hostname=worker$((index+1))
  nodeIP=${nodesIP[$index]}
  eval sed 's/worker_address/${nodeIP}/g' ./rancher-cluster/worker >worker_tmp
  eval sed -i 's/worker_hostname/${hostname}/g' worker_tmp
  paste worker_tmp  >> rancher_cluster.yml
  rm -rf worker_tmp
done
paste ./rancher-cluster/other >> rancher_cluster.yml

