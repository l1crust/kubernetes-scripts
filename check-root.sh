#!/bin/bash

CONTAINERS=0
print_usage(){
    echo "$0 [-n <NAMESPACE ] [-v]"
    echo "example: $0 -n kube-system"
    exit 0
}


check_root_pods_namespace(){
    namespace=$1
    pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" -n $namespace)
    for pod in $pods ; do
        echo "Check pod $pod"
        if [[ $CONTAINERS -eq 0 ]] ; then
            kubectl exec -it $pod -n $namespace -- id 2>/dev/null
        else
            containers=$(kubectl get pods $pod -n $namespace -o=jsonpath='{.spec.containers[*].name}*')
            for c in $containers ; do
                echo "Check container $c"
                kubectl exec -it $pod -n $namespace -c $c -- id 2>/dev/null
            done     
        fi   
    done
}

# Parsing arguments
while getopts n:vh option
do 
    case "${option}"
        in
        n)namespace=${OPTARG};;
        v)CONTAINERS=1;;
        h)print_usage
    esac
done


if [[ -z $namespace ]]; then
    namespaces=$(kubectl get ns --no-headers -o custom-columns=":metadata.name")
    for ns in $namespaces ; do 
        echo "+ Pods in namespace $ns"
        check_root_pods_namespace $ns
    done
else
    check_root_pods_namespace $namespace
fi



