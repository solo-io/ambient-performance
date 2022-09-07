#!/bin/bash

dir="$( cd "$( dirname "$0" )" && pwd )"
config_file=${CONFIG_FILE:-"$dir/config.yaml"}

SERVICE_PORT_NAME=`yq '.service_port_name' "$config_file"`
if [[ "$SERVICE_PORT_NAME" == "null" ]]; then
    SERVICE_PORT_NAME="tcp-enforcement"
fi

PARAMS=`yq '.params' "$config_file"`
if [[ "$PARAMS" == "null" ]]; then
    echo "No params specified in config.yaml"
    exit 1
fi
CONTEXT=`yq '.context' "$config_file"`
if [[ "$CONTEXT" == "null" ]]; then
    echo "No context specified in config.yaml"
    exit 1
fi

IMAGE_PULL_SECRET=`yq '.image_pull_secret' "$config_file"`

# check if IMAGE_PULL_SECRETis null and zero it if so
if [[ "$IMAGE_PULL_SECRET" == "null" ]]; then
    IMAGE_PULL_SECRET=""
fi

TEST_TYPE=`yq '.test_type' "$config_file"`
if [[ "$TEST_TYPE" == "null" ]]; then
    TEST_TYPE="http"
fi

COUNT=`yq '.count' "$config_file"`
if [[ "$COUNT" == "null"  ]]; then
    COUNT="1000"
fi

CONTINUE_ON_FAIL=`yq '.continue_on_fail' "$config_file"`
if [[ "$CONTINUE_ON_FAIL" == "null"  ]]; then
    CONTINUE_ON_FAIL="yes"
fi

FINAL_RESULT=`yq '.final_result' "$config_file"`
if [[ "$FINAL_RESULT" == "null"  ]]; then
    FINAL_RESULT="/tmp/results.txt"
fi

ISTIOCTL_PATH=`yq '.istioctl_path' "$config_file"`

HUB=`yq '.hub' "$config_file"`
TAG=`yq '.tag' "$config_file"`

PERF_CLIENT=`yq '.perf_client' "$config_file"`
if [[ "$PERF_CLIENT" == "null"  ]]; then
    PERF_CLIENT="nighthawk"
fi

TEST_WAIT=`yq '.test_wait' "$config_file"`
if [[ "$TEST_WAIT" == "null"  ]]; then
    TEST_WAIT="1"
fi

SERVER_SCALE=`yq '.server_scale' "$config_file"`
if [[ "$SERVER_SCALE" == "null"  ]]; then
    SERVER_SCALE="1"
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

NUM_CLUSTERS=`yq '.clusters | length' "$config_file"`
for i in $(seq 0 $((${NUM_CLUSTERS} - 1))); do

    # jq -er '.context | values
    # -e - return error if output is null
    # '| values' doesn't output null
    # see https://github.com/stedolan/jq/issues/354#issuecomment-478771540
    CONTEXT_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].context | values' || echo $CONTEXT)
    K8S_TYPE_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].k8s_type | values' || echo $K8S_TYPE)
    SERVICE_PORT_NAME_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].service_port_name | values' || echo $SERVICE_PORT_NAME)
    PARAMS_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].params | values' || echo $PARAMS)
    IMAGE_PULL_SECRET=$(yq -o json "$config_file" | jq -er '.clusters['$i'].image_pull_secret | values' || echo $IMAGE_PULL_SECRET)
    TEST_TYPE_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].test_type | values' || echo $TEST_TYPE)
    COUNT_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].count | values' || echo $COUNT)
    PERF_CLIENT_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].perf_client | values' || echo $PERF_CLIENT)
    TEST_WAIT_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].test_wait | values' || echo $TEST_WAIT)
    SERVER_SCALE_CLUSTER=$(yq -o json "$config_file" | jq -er '.clusters['$i'].server_scale | values' || echo $SERVER_SCALE)

    if [[ "$TEST_TYPE_CLUSTER" != "http" && "$TEST_TYPE_CLUSTER" != "tcp" && "$TEST_TYPE_CLUSTER" != "tcp-throughput" ]]; then
        echo "Invalid test type: $TEST_TYPE_CLUSTER... skipping $CONTEXT_CLUSTER"
        continue
    fi

    RESULT_FILE=$(yq -o json "$config_file" | jq -r '.clusters['$i'].result_file | values')
    if [[ -z "$RESULT_FILE" ]]; then
        RESULT_FILE="/tmp/results.csv"
    fi
    if [[ "$TEST_TYPE_CLUSTER" == "http" ]]; then
        if [[ "$SERVICE_PORT_NAME_CLUSTER" == "http" ]]; then
            protocol="HTTP (w/ mTLS Layer 7 parsing)"
        else
            protocol="HTTP (w/o mTLS Layer 7 parsing)"
        fi
    elif [[ "$TEST_TYPE_CLUSTER" == "tcp-throughput" ]]; then
        protocol="TCP Throughput"
    else
        protocol="TCP Latency"
    fi

    while true; do
        log "Running tests for cluster: $CONTEXT_CLUSTER"
        log "Test type: $TEST_TYPE_CLUSTER"
        if [[ "$TEST_TYPE_CLUSTER" == "http" ]]; then
            log "Running test: " ISTIOCTL_PATH="$ISTIOCTL_PATH" SERVICE_PORT_NAME="$SERVICE_PORT_NAME_CLUSTER" PERF_CLIENT_PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" TEST_WAIT="$TEST_WAIT_CLUSTER" SERVER_SCALE="$SERVER_SCALE_CLUSTER" PERF_CLIENT="$PERF_CLIENT_CLUSTER" ./lib/http_perf_tests.sh
            ISTIOCTL_PATH="$ISTIOCTL_PATH" SERVICE_PORT_NAME="$SERVICE_PORT_NAME_CLUSTER" PERF_CLIENT_PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" TEST_WAIT="$TEST_WAIT_CLUSTER" SERVER_SCALE="$SERVER_SCALE_CLUSTER" PERF_CLIENT="$PERF_CLIENT_CLUSTER" ./lib/http_perf_tests.sh
        else
            log "Running test: " ISTIOCTL_PATH="$ISTIOCTL_PATH" TEST_TYPE="$TEST_TYPE_CLUSTER" COUNT="$COUNT_CLUSTER" PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" ./lib/tcp_perf_tests.sh
            ISTIOCTL_PATH="$ISTIOCTL_PATH" TEST_TYPE="$TEST_TYPE_CLUSTER" COUNT="$COUNT_CLUSTER" PARAMS="$PARAMS_CLUSTER" RESULTS_FILE="$RESULT_FILE" CONTEXT="$CONTEXT_CLUSTER" K8S_TYPE="$K8S_TYPE_CLUSTER" HUB="$HUB" TAG="$TAG" IMAGE_PULL_SECRET="$IMAGE_PULL_SECRET" ./lib/tcp_perf_tests.sh
        fi
        
        EXIT_CODE=$?
        if [[ $EXIT_CODE -ne 0 ]]; then
            # 2 is ctrl+c exit
            if [[ $EXIT_CODE -eq 2 ]]; then
                exit 2
            fi
            log "Failed to run tests for $CONTEXT_CLUSTER, parameters: $PARAMS_CLUSTER"
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

    if [[ $PERF_CLIENT == "nighthawk" ]]; then
        sleep 5 # Give time for file to be written to disk

        echo "Benchmark client parameters: $PARAMS_CLUSTER" | tee -a "$FINAL_RESULT"
        echo "Protocol: $protocol" | tee -a "$FINAL_RESULT"
        echo "------------- $CONTEXT_CLUSTER -------------" | tee -a "$FINAL_RESULT"
        RESULTS_FILE="$RESULT_FILE" ./conv_results.sh | tee -a "$FINAL_RESULT"
    fi
done
