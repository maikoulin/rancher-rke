#!/bin/bash
set -eu

admin_password=$1
rancher_ip=$2
cluster_name=$3
curlimage="hub.local:5000/lucashalbert/curl"
jqimage="hub.local:5000/imega/jq"

#install rancher v2.6.2
mkdir -p /opt/rancher
cp ./config/registries.yaml  /opt/rancher/

docker run -d --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -e CATTLE_SYSTEM_DEFAULT_REGISTRY="hub.local:5000" \
  -e CATTLE_AGENT_IMAGE="hub.local:5000/rancher/rancher-agent:v2.6.2" \
  -v /opt/rancher/registries.yaml:/etc/rancher/k3s/registries.yaml \
  --add-host="hub.local:${rancher_ip}" \
  --privileged \
  hub.local:5000/rancher/rancher:v2.6.2 

# wait until rancher server is ready
num=1

while true
do
    echo "check rancher status"
    status=$(docker run --rm --net=host $curlimage -sLk "https://${rancher_ip}/ping" || echo "installing")
    echo "status = $status"
    if [[ $status == "pong" ]] ; then
       echo "install ok"
       break
    else
        echo "wait rancher installed"
        sleep 5
    fi
    num=`expr $num + 1`
    if [[ $num == 50 ]]; then
        echo "rancher install failed"
        exit -1
        break
    fi
done

#cut rancher original  password
CONTAINERID=$(docker ps | grep rancher: | cut -d " " -f 1)
ORIGINALPASSWORD=$(docker logs  ${CONTAINERID}  2>&1 | grep "Bootstrap Password:" | cut -d " " -f 6)

echo "CONTAINERID=$CONTAINERID"
echo "ORIGINALPASSWORD=$ORIGINALPASSWORD"

sleep 10
# Login

num=1
while true
do

    LOGINRESPONSE=$(docker run \
        --rm \
        --net=host \
        $curlimage \
        -s "https://${rancher_ip}/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"'$ORIGINALPASSWORD'"}' --insecure || echo '{"status":"installing"}')

    echo "LOGINRESPONSE=$LOGINRESPONSE"
      
     {
       LOGINTOKEN=$(echo $LOGINRESPONSE | docker run --rm -i $jqimage -r .token) 
     } || {
       LOGINTOKEN="null"
     }
      
    if [ "$LOGINTOKEN" != "null" ]; then
             break
    else
            sleep 5
    fi

    num=`expr $num + 1`
    if [[ $num == 50 ]]; then
        echo "rancher install failed"
        exit -1
        break
    fi

done

echo "LOGINRESPONSE=$LOGINRESPONSE"
echo "LOGINTOKEN=$LOGINTOKEN"

sleep 10

#Change password
docker run --rm --net=host $curlimage -s "https://${rancher_ip}/v3/users?action=changepassword" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"currentPassword":"'$ORIGINALPASSWORD'","newPassword":"'$admin_password'"}' --insecure

sleep 5
#Create API key
APIRESPONSE=$(docker run --rm --net=host $curlimage -s "https://${rancher_ip}/v3/token" -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"type":"token","description":"automation"}' --insecure)
echo "APIRESPONSE=$APIRESPONSE"

#Extract and store token
APITOKEN=`echo $APIRESPONSE | docker run --rm -i $jqimage -r .token`
echo "APITOKEN=$APITOKEN"

sleep 5

# Configure server-url
RANCHER_SERVER="https://${rancher_ip}"
docker run --rm --net=host $curlimage -s "https://${rancher_ip}/v3/settings/server-url" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"server-url","value":"'$RANCHER_SERVER'"}' --insecure

sleep 5

# Create cluster
CLUSTERRESPONSE=$(docker run --rm --net=host $curlimage -s "https://${rancher_ip}/v3/cluster?_replace=true" -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"dockerRootDir":"/var/lib/docker","enableClusterAlerting":false,"enableClusterMonitoring":false,"enableNetworkPolicy":false,"windowsPreferedCluster":false,"type":"cluster","name":"'${cluster_name}'","agentEnvVars":[],"labels":{}}' --insecure)
echo "CLUSTERRESPONSE=$CLUSTERRESPONSE"

# Extract clusterid to use for generating the docker run command
#CLUSTERID=`echo $CLUSTERRESPONSE | docker run --rm -i $jqimage -r .id`

sleep 5

# Generate registrationtoken
REGISTRATIONTOKEN=$(docker run --rm --net=host $curlimage -s 'https://'${rancher_ip}'/v3/clusterregistrationtoken?limit=-1' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN"  --insecure)

echo "REGISTRATIONTOKEN=$REGISTRATIONTOKEN"

#import rke cluster to rancher 
INSECURECOMMAND=`echo $REGISTRATIONTOKEN | docker run --rm -i $jqimage -r  .data[0].insecureCommand`

echo $INSECURECOMMAND 

eval $INSECURECOMMAND

