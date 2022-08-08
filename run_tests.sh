#!/bin/bash

dir="$( cd "$( dirname "$0" )" && pwd )"
config_file=${CONFIG_FILE:-"$dir/config.yaml"}

SERVICE_PORT_NAME=`yq '.service_port_name' "$config_file"`
if [ -z "$SERVICE_PORT_NAME" ]; then
    SERVICE_PORT_NAME="tcp-enforcement"
fi

PARAMS=`yq '.params' "$config_file"`
if [[ -z "$PARAMS" ]]; then
    echo "No params specified in config.yaml"
    exit 1
fi
CONTEXT=`yq '.context' "$config_file"`
K8S_TYPE=`yq '.k8s_type' "$config_file"`
IMAGE_PULL_SECRET=`yq '.image_pull_secret' "$config_file"`

CONTINUE_ON_FAIL=`yq '.continue_on_fail' "$config_file"`
if [[ -z "$CONTINUE_ON_FAIL" ]]; then
    CONTINUE_ON_FAIL="yes"
fi

FINAL_RESULT=`yq '.final_result' "$config_file"`
if [[ -z "$FINAL_RESULT" ]]; then
    FINAL_RESULT="/tmp/results.txt"
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

EOF

if [[ -f "log" ]]; then
    mv "log" "log-$(date +%Y%m%d-%H%M%S)"
fi

log() {
    # -Is is not standard, so let's pass args instead
    d=$(date +%FT%T%:z)
    echo "[$d] $*" | tee -a "log"
}

cat $config_file | yq -o json | jq -c '.clusters[]' | while read i
do
    # jq -er '.context | values
    # -e - return error if output is null
    # '| values' doesn't output null
    # see https://github.com/stedolan/jq/issues/354#issuecomment-478771540
    CONTEXT_CLUSTER=$(echo $i | jq -er '.context | values' || echo $CONTEXT)
    K8S_TYPE_CLUSTER=$(echo $i | jq -er '.k8s_type | values' || echo $K8S_TYPE)
    SERVICE_PORT_NAME_CLUSTER=$(echo $i | jq -er '.service_port_name | values' || echo $SERVICE_PORT_NAME)
    PARAMS_CLUSTER=$(echo $i | jq -er '.params | values' || echo $PARAMS)
    IMAGE_PULL_SECRET=$(echo $i | jq -er '.image_pull_secret | values' || echo $IMAGE_PULL_SECRET)

    if [[ "$IMAGE_PULL_SECRET" == "null" ]]; then
        IMAGE_PULL_SECRET=""
    fi

    RESULT_FILE=`echo $i | jq -r '.result_file | values'`
    if [[ -z "$RESULT_FILE" ]]; then
        RESULT_FILE="/tmp/results.txt"
    fi

    while true; do
        log "Running tests for cluster: $CONTEXT_CLUSTER"
        log "Running test: " SERVICE_PORT_NAME="$SERVICE_PORT_NAME_CLUSTER" NIGHTHAWK_PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" ./perf_tests.sh
        SERVICE_PORT_NAME="$SERVICE_PORT_NAME_CLUSTER" NIGHTHAWK_PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" ./perf_tests.sh
        
        EXIT_CODE=$?
        if [[ $EXIT_CODE -ne 0 ]]; then
            # 2 is ctrl+c exit
            if [[ $EXIT_CODE -eq 2 ]]; then
                exit 2
            fi
            log "Failed to run tests for $CONTEXT_CLUSTER with protocol: $protocol, parameters: $PARAMS_CLUSTER"
            if [[ "$CONTINUE_ON_FAIL" == "yes" ]]; then
                log "Continuing on fail, going to next cluster"
                break
            fi
            log "Waiting 30 seconds and restarting test."
            sleep 30
        elif [[ $EXIT_CODE -eq 0 ]]; then
            break
        fi
    done

    sleep 5 # Give time for file to be written to disk

    echo "Nighthawk client parameters: $PARAMS_CLUSTER" | tee -a "$FINAL_RESULT"
    echo "Protocol: $protocol ($SERVICE_PORT_NAME_CLUSTER)" | tee -a "$FINAL_RESULT"
    echo "------------- $CONTEXT_CLUSTER -------------" | tee -a "$FINAL_RESULT"
    RESULTS_FILE="$RESULT_FILE" ./conv_results.sh | tee -a "$FINAL_RESULT"
done