#!/bin/bash

dir="$( cd "$( dirname "$0" )" && pwd )"
config_file="$dir/config.yaml"

SERVICE_PORT_NAME=`yq '.service_port_name' "$config_file"`
if [ -z "$SERVICE_PORT_NAME" ]; then
    SERVICE_PORT_NAME="tcp-enforcement"
fi

PARAMS=`yq '.params' "$config_file"`
if [[ -z "$PARAMS" ]]; then
    echo "No params specified in config.yaml"
    exit 1
fi

FINAL_RESULT=`yq '.final_result' "$config_file"`
if [[ -z "$FINAL_RESULT" ]]; then
    FINAL_RESULT="/tmp/results.txt"
fi

LINKERD=`yq '.linkerd' "$config_file"`
if [[ -z "$LINKERD" ]] || [[ "$LINKERD" == false ]]; then
    LINKERD=""
else
    LINKERD="1"
fi

HUB=`yq '.hub' "$config_file"`
TAG=`yq '.tag' "$config_file"`

if [[ "$SERVICE_PORT_NAME" == "http" ]]; then
    protocol="HTTP (w/ mTLS Layer 7 parsing)"
else
    protocol="HTTP (w/o mTLS Layer 7 parsing)"
fi

cat <<EOF > "$FINAL_RESULT"
Test run: $(date)
Nighthawk client parameters: $PARAMS
Protocol: $protocol

EOF

cat $config_file | yq -o json | jq -c '.clusters[]' | while read i
do
    CONTEXT=`echo $i | jq -r '.context'`
    K8S_TYPE=`echo $i | jq -r '.k8s_type'`
    RESULT_FILE=`echo $i | jq -r '.result_file'`

    LINKERD=$LINKERD SERVICE_PORT_NAME="$SERVICE_PORT_NAME" NIGHTHAWK_PARAMS="$PARAMS" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT" K8S_TYPE="$K8S_TYPE" HUB="$HUB" TAG="$TAG" ./run_perf_tests.sh

    if [[ $? -ne 0 ]]; then
        echo "Failed to run tests for $CONTEXT"
        exit 1
    fi

    sleep 5 # Give time for file to be written to disk

    echo "------------- $CONTEXT -------------" | tee -a "$FINAL_RESULT"
    RESULTS_FILE="$RESULT_FILE" ./conv_results.sh | tee -a "$FINAL_RESULT"
done
