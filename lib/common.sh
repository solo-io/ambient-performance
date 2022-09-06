#!/bin/bash

# Setup some variable defaults, these should be read from the environment
startTime=$(date +%s)
DIR="$( cd "$( dirname "$0" )" && pwd )"
TMPDIR=$(mktemp -d)
NIGHTHAWK_PARAMS=${NIGHTHAWK_PARAMS:-"--concurrency 1 --output-format json --rps 200 --duration 60"}
# NIGHTHAWK_PARAMS="--concurrency 1 --output-format json --max-requests-per-connection 1 --rps 200 --duration 60"
SERVICE_PORT_NAME=${SERVICE_PORT_NAME:-"tcp-enforcment"}
AMBIENT_REPO_DIR=${AMBIENT_REPO_DIR:-"$DIR/../../istio-sidecarless"}
DATERUN=$(date +"%Y%m%d-%H%M")
TESTING_NAMESPACE="test-$DATERUN"
RESULTS_JSON=${RESULTS_JSON:-"$TMPDIR/results-$DATERUN.json"}
RESULTS_FILE=${RESULTS_FILE:-"$DIR/results/results-$DATERUN.csv"}
if [[ ! -z "$CONTEXT" ]]; then
    CONTEXT="--context $CONTEXT"
fi

IMAGE_PULL_SECRET_NAME=""
if [[ ! -z "$IMAGE_PULL_SECRET" ]]; then
    if [[ -f "$IMAGE_PULL_SECRET" ]]; then
        IMAGE_PULL_SECRET_NAME=`cat "$IMAGE_PULL_SECRET" | yq '.metadata.name'`
        if [[ $? -ne 0 ]]; then
            echo "Error: could not parse image pull secret name from $IMAGE_PULL_SECRET"
            exit 1
        fi
        IMAGE_PULL_SECRET_NAME=`echo $IMAGE_PULL_SECRET_NAME | tr -d '"'`
    else
        echo "Image pull secret should be a file: '$IMAGE_PULL_SECRET'"
        exit 1
    fi
fi

RESULTS_NAMES=()
RESULTS_P50=()
RESULTS_P90=()
RESULTS_P95=()
RESULTS_P99=()
RESULTS_P999=()
RESULTS_P9999=()
RESULTS_MEAN=()
RESULTS_STDDEV=()
RESULTS_MAX=()
RESULTS_MIN=()

RESULTS_RECV_P50=()
RESULTS_RECV_P90=()
RESULTS_RECV_P95=()
RESULTS_RECV_P99=()
RESULTS_RECV_P999=()
RESULTS_RECV_P9999=()
RESULTS_RECV_MEAN=()
RESULTS_RECV_STDDEV=()
RESULTS_RECV_MAX=()
RESULTS_RECV_MIN=()
RESULTS_SEND_P50=()
RESULTS_SEND_P90=()
RESULTS_SEND_P95=()
RESULTS_SEND_P99=()
RESULTS_SEND_P999=()
RESULTS_SEND_P9999=()
RESULTS_SEND_MEAN=()
RESULTS_SEND_STDDEV=()
RESULTS_SEND_MAX=()
RESULTS_SEND_MIN=()

if [[ ! -d "results" ]]; then
    mkdir "results"
fi

###############################################################################################################################
# Shared functions

kctl() {
    kubectl $CONTEXT "$@"
}

log() {
    # -Is is not standard, so let's pass args instead
    d=$(date +%FT%T%:z)
    echo "[$d] $*" | tee -a "log"
}

writeResults() {
    echo "Run time: $(date)" > "$RESULTS_FILE"
    if [[ -z "$PARAMS" ]]; then
        echo "Benchmark parameters: $NIGHTHAWK_PARAMS" >> "$RESULTS_FILE"
    else
        echo "Benchmark Parameters: $PARAMS" >> "$RESULTS_FILE"
    fi
    if [[ -z "$COUNT" ]]; then
        echo "Service port name: $SERVICE_PORT_NAME" >> "$RESULTS_FILE"
    else
        echo "TCP Connection Count: $COUNT" >> "$RESULTS_FILE"
    fi

    printf "\n," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_NAMES[$i]}," >> "$RESULTS_FILE"; done

    printf "\np50," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P50[$i]}," >> "$RESULTS_FILE"; done

    printf "\np90," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P90[$i]}," >> "$RESULTS_FILE"; done

    printf "\np95," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P95[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P99[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.9," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P999[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.99," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P9999[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMean," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_MEAN[$i]}," >> "$RESULTS_FILE"; done
    printf "\nStddev," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_STDDEV[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMax," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_MAX[$i]}," >> "$RESULTS_FILE"; done
    printf "\nMin," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_MIN[$i]}," >> "$RESULTS_FILE"; done

    printf "\n" >> "$RESULTS_FILE"
}

writeThroughputResults() {
    echo "Run time: $(date)" > "$RESULTS_FILE"
    if [[ -z "$PARAMS" ]]; then
        echo "Benchmark parameters: $NIGHTHAWK_PARAMS" >> "$RESULTS_FILE"
    else
        echo "Benchmark Parameters: $PARAMS" >> "$RESULTS_FILE"
    fi
    if [[ -z "$COUNT" ]]; then
        echo "Service port name: $SERVICE_PORT_NAME" >> "$RESULTS_FILE"
    else
        echo "TCP Connection Count: $COUNT" >> "$RESULTS_FILE"
    fi

    printf "\n," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_NAMES[$i]}," >> "$RESULTS_FILE"; done

    printf "\np50 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P50[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np50 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P50[$i]}," >> "$RESULTS_FILE"; done

    printf "\np90 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P90[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np90 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P90[$i]}," >> "$RESULTS_FILE"; done

    printf "\np95 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P95[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np95 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P95[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P99[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np99 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P99[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.9 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P999[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np99.9 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P999[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.99 send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_P9999[$i]}," >> "$RESULTS_FILE"; done
#    printf "\np99.99 recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_P9999[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMean send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_MEAN[$i]}," >> "$RESULTS_FILE"; done
#    printf "\nMean recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_MEAN[$i]}," >> "$RESULTS_FILE"; done

    printf "\nStddev send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_STDDEV[$i]}," >> "$RESULTS_FILE"; done
#    printf "\nStddev recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_STDDEV[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMin send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_MIN[$i]}," >> "$RESULTS_FILE"; done
#    printf "\nMin recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_MIN[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMax send," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_SEND_MAX[$i]}," >> "$RESULTS_FILE"; done
#    printf "\nMax recv," >> "$RESULTS_FILE"
#    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_RECV_MAX[$i]}," >> "$RESULTS_FILE"; done

    printf "\n" >> "$RESULTS_FILE"
}

applyMutualTLS() {
    log "Applying strict mTLS"
    cat <<EOF | kctl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
}

installIstio() {
    secret=""
    if [[ "$IMAGE_PULL_SECRET_NAME" != "" ]]; then
        log "Creating IstioOperator for imagePullSecrets"
        cat <<EOF >$TMPDIR/imagepullsecrets.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      imagePullSecrets:
        - $IMAGE_PULL_SECRET_NAME
EOF
        secret="-f $TMPDIR/imagepullsecrets.yaml"

        log "Creating istio-system and applying the image pull secret"
        kctl create ns istio-system
        kctl apply -n istio-system -f $IMAGE_PULL_SECRET
    fi

    log "Installing Istio"
    go run istioctl/cmd/istioctl/main.go install $CONTEXT -d manifests/ --set hub="$HUB" --set tag="$TAG" -y $@ $secret --set values.global.imagePullPolicy=Always
    if [[ $? -ne 0 ]]; then
        log "Error: istioctl install failed"
        return 1
    fi

    if [[ -f "$TMPDIR/imagepullsecrets.yaml" ]]; then
        log "Removing temporary image pull secret yaml"
        rm "$TMPDIR/imagepullsecrets.yaml"
    fi
}

applyImagePullSecret() {
    if [[ "$IMAGE_PULL_SECRET_NAME" != "" ]]; then
        log "Applying image pull secret to namespace $1"
        kctl apply -n $1 -f $IMAGE_PULL_SECRET
    fi
}


cleanupCluster() {
    log "Cleaning up cluster"
    go run istioctl/cmd/istioctl/main.go uninstall --purge -y $CONTEXT || true
    kctl delete -n $TESTING_NAMESPACE -f "$DIR/../yaml" || true
    kctl delete ns istio-system || true
    kctl delete ns $TESTING_NAMESPACE || true
}

trapCtrlC() {
    log "Caught CTRL-C, cleaning up cluster"
    cleanupCluster
    exit 2
}

runTest() {
    while true; do
        log "Running test $1"
        "$2"
        ec=$?
        cleanupCluster
        if [[ "$ec" != "0" ]]; then
            log "Error: test $1 failed... will wait 30 seconds and retry (ec=$ec)"
            sleep 30
        else
            log "Test $1 succeeded (ec=$ec)"
            break
        fi
    done
}

. $DIR/tests.sh

pushd "$AMBIENT_REPO_DIR" || exit

trap "trapCtrlC" 2

# Run the tests
# These are in loops as EKS has proven to be predictably unpredictable on if a test will actually complete..
# so on failure, clean up.. wait.. and just try again
runTests

popd || exit

log "All tests completed, writing results"

if [[ $TEST_TYPE == "tcp-throughput" ]]; then
    writeThroughputResults
else
    writeResults
fi

endTime=$(date +%s)
duration=$((endTime - startTime))
log `LC_NUMERIC=C printf "Total runtime: %d\n" $duration`
