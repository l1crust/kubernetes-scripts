#!/bin/bash

print_usage(){
    echo "$0 -n <NAMESPACE> [-p <POD_NAME> [-c <CONTAINER_NAME>] [-i <IPs_TO_SCAN>]"
    echo "example: $0 -n kube-system -p kube-dns-848f988bc4-v7m26 -i \"127.0.0.1 10.101.5.4 10.101.5.6\""
    exit 0
}

# Check in container if tool can be use to scan: ping / curl 
# $1: namespace, $2: pod, $3 container
select_scan_tool(){
    # Check ping
    res=$(kubectl exec -it $2 -c $3 -n $1 -- which ping 2>/dev/null)
    if [[ -n $res ]] && [[ $res != *"no ping in"* ]] ; then
        res=$(kubectl exec -it $2 -c $3 -n $1 -- ping -c 1 -w 1 127.0.0.1 2>&1)
        if [[ $res != *"permission denied"* ]] && [[ $res != *"operation not permitted"* ]] ; then
            echo $res
            return 1 # ping
        fi
    fi

    # check curl
    res=$(kubectl exec -it $2 -c $3 -n $1 -- which curl 2>/dev/null)
    if [[ -n $res ]]; then
        return 2 # curl
    fi

    # check wget 
    res=$(kubectl exec -it $2 -c $3 -n $1 -- which wget 2>/dev/null)
    if [[ -n $res ]]; then
        return 3 # wget
    fi
    return 0 # none 
}


# Scan specified IP from container
# $1: namespace, $2: pod, $3: container, $4: ipList
scan(){
    namespace=$1
    pod=$2
    container=$3
    podIpList=$4

    select_scan_tool $namespace $pod $container
    scanTool=$?
    echo "Scanning IP from $pod/$container, using $scanTool (1:ping, 2:curl, 3:wget, 0: none)"
    # if ping
    if [[ $scanTool == 1 ]]; then
        #cmd="for ip in $podIpList;do res="'$(ping -c 1 -W 1 $ip);if [[ $res == *"1 received"* ]]; then echo "+ $ip";fi;done'
        for ip in $podIpList;do
            res=$(kubectl exec -it $pod -c $container -n $namespace -- ping -c 1 -W 1 $ip 2>/dev/null) 2>/dev/null
            if [[ $res == *"1 received"* ]];then 
                echo "+ $ip: ${pods[$ip]}"
            elif [[ $res == "" ]] || [[ $res == *"permission denied"* ]] || [[ $res == *"operation not permitted"* ]]; then
                echo "cannot ping"
                break
            fi
        done
    # if curl
    elif [[ $scanTool == 2 ]]; then
        for ip in $podIpList;do
            res=$(kubectl exec -it $pod -c $container -n $namespace -- curl -s -m 1 $ip &>/dev/null ; if [ ! $? -eq 28 ]; then echo "up"; fi)
            if [[ $res == "up" ]];then 
                echo "+ $ip: ${pods[$ip]}"
            elif [[ $res == "not found" ]] || [[ $res == *"permission denied"* ]]; then
                echo "cannot curl"
                break
            fi
        done
    # if wget
    elif [[ $scanTool == 3 ]]; then
        for ip in $podIpList; do
            res=$(kubectl exec -it $pod -c $container -n $namespace -- wget -S -qO- $ip -t 1 -T 2 2>&1) 
            if [[ $res == *"HTTP"* ]] || [[ $res == *"Connection refused"* ]] ; then #  elif [[ $res == *"timed out"* ]] ; then echo "ko" ; else echo "error" 
                echo "+ $ip: ${pods[$ip]}"
            elif [[ $res != *"timed out"* ]] ; then
                echo "Error wget: $res"
            fi
        done
    else echo "Cannot scan, unavailable scan tool (ping, curl or wget)."
    fi
}

# Parsing arguments
while getopts n:p:c:i:h option
do 
    case "${option}"
        in
        n)namespace=${OPTARG};;
        p)pods=${OPTARG};;
        c)containers=${OPTARG};;
        i)ipToScan=${OPTARG};;  
        h)print_usage
    esac
done


if [[ -z $namespace ]]; then
    echo "Missing namespace argument"
    print_usage
    exit 1
fi
if [[ -z $pods ]]; then
    pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n $namespace)
fi

# Get name and IP address for all pods in the cluster (all namespaces)
    podList=$(kubectl get pods -A -o=jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.metadata.name}{"\n"}{end}')
    declare -A pods
    while read line ; do
        podName=$(echo "$line" | cut -d " " -f 2)
        podIp=$(echo "$line" | cut -d " " -f 1)
        pods[$podIp]="$podName"
    done <<< "$podList"

if [[ -z $ipToScan ]]; then
    # Build list of IP
    ipToScan=""
    for key in "${!pods[@]}"; do
        if [[ $key != 0 ]]; then
            ipToScan="$ipToScan $key"
        fi
    done
fi


# 3. Run 
# echo "Start ping scan pods in cluster from $namespace namespace"
for pod in $pods; do
	if [[ -z $containers ]]; then
	    containerstmp=$(kubectl get pods $pod -n $namespace -o=jsonpath='{.spec.containers[*].name}*')
    else 
        containerstmp=$containers
	fi
    for containertmp in $containerstmp ; do 
        # Sometime result container name ends with extra *, that needs to be removed
        if [ -z "${containertmp##*"*"}" ]; then
            container="${containertmp//\*}"
        else
            container="$containertmp"
        fi
        scan "$namespace" "$pod" "$container" "$ipToScan"
    done
done
