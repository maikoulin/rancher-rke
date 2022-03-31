#!/bin/bash
set -eu

echo "install rancher-logging"
#install rancher-logging 
helm install rancher-logging-crd ./install-apps/rancher-logging/rancher-logging-crd/100.0.0+up3.12.0 --create-namespace -n  cattle-logging-system

sleep 10

helm install rancher-logging ./install-apps/rancher-logging/rancher-logging/100.0.0+up3.12.0 --create-namespace -n  cattle-logging-system &

echo "install rancher-monitoring"
#install rancher-monitoring
helm install rancher-monitoring-crd ./install-apps/rancher-monitoring/rancher-monitoring-crd/100.0.0+up16.6.0 --create-namespace -n cattle-monitoring-system

sleep 10

helm install rancher-monitoring ./install-apps/rancher-monitoring/rancher-monitoring/100.0.0+up16.6.0 --create-namespace -n cattle-monitoring-system 

sleep 10

#install rancher-alerting-drivers
helm install rancher-alerting-drivers ./install-apps/rancher-alerting-drivers/rancher-alerting-drivers/100.0.0 --create-namespace -n cattle-monitoring-system &

sleep 10

#install dingtalk
helm install dingtalk  ./install-apps/dingtalk --create-namespace -n cattle-monitoring-system &

sleep 10

echo "install istio"
#install istio
helm install rancher-istio ./install-apps/rancher-istio --create-namespace -n istio-system
