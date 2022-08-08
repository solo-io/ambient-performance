#!/bin/bash

# Setup some variable defaults, these should be read from the environment
start=$(date +%s)
DIR="$( cd "$( dirname "$0" )" && pwd )"
TMPDIR=$(mktemp -d)
NIGHTHAWK_PARAMS=${NIGHTHAWK_PARAMS:-"--concurrency 1 --output-format json --rps 200 --duration 60"}
# NIGHTHAWK_PARAMS="--concurrency 1 --output-format json --max-requests-per-connection 1 --rps 200 --duration 60"
SERVICE_PORT_NAME=${SERVICE_PORT_NAME:-"tcp-enforcment"}
AMBIENT_REPO_DIR=${AMBIENT_REPO_DIR:-"$DIR/../istio-sidecarless"}
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

runPerfTest() {
    test_name=$1

    if [[ "$2" == "skip" ]]; then
        log "Skipping test: $test_name"
        RESULTS_NAMES+=("$test_name")
        RESULTS_P50+=("Skipped")
        RESULTS_P90+=("Skipped")
        RESULTS_P95+=("Skipped")
        RESULTS_P99+=("Skipped")
        RESULTS_P999+=("Skipped")
        RESULTS_P9999+=("Skipped")
        RESULTS_MEAN+=("Skipped")
        RESULTS_STDDEV+=("Skipped")
        RESULTS_MAX+=("Skipped")
        RESULTS_MIN+=("Skipped")
        return 0
    fi

    log "Executing performance tests for: $test_name..."
    eval kctl exec -n $TESTING_NAMESPACE deploy/nhclient -c nighthawk -- \
        nighthawk_client "$NIGHTHAWK_PARAMS" http://nhserver:8080/ > "$RESULTS_JSON"
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_client failed"
        return 1
    fi

    RESULTS_NAMES+=("$test_name")
    RESULTS_P50+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.5).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P90+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P95+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.95).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P99+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.990625).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P9999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.99990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MEAN+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.mean)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_STDDEV+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.pstdev)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MAX+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.max)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MIN+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.min)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");

    rm "$RESULTS_JSON"
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

deployWorkloads() {
    log "Deploying workloads"
    sed "s/tcp-enforcement/$SERVICE_PORT_NAME/g" "$DIR/yaml/perf-test.yaml" | kctl -n $TESTING_NAMESPACE apply -f -
    log "Deployments applied to cluster, waiting for pods to be ready"
    sleep 5 # Can take time for the deployment to be known to the Kubernetes API
    kctl wait pods -n $TESTING_NAMESPACE -l app=nhclient --for=condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_client pod failed to start"
        return 1
    fi
    kctl wait pods -n $TESTING_NAMESPACE -l app=nhserver --for=condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_server pod failed to start"
        return 1
    fi
    sleep 5
}

writeResults() {
    echo "Run time: $(date)" > "$RESULTS_FILE"
    echo "Nighthawk client parameters: $NIGHTHAWK_PARAMS" >> "$RESULTS_FILE"
    echo "Service port name: $SERVICE_PORT_NAME" >> "$RESULTS_FILE"

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

cleanupCluster() {
    log "Cleaning up cluster"
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT || true
    kctl delete -n $TESTING_NAMESPACE -f "$DIR/yaml" || true
    kctl delete ns istio-system || true
    kctl delete ns $TESTING_NAMESPACE || true
}

trapCtrlC() {
    log "Caught CTRL-C, cleaning up cluster"
    cleanupCluster
    exit 2
}

#########################################################################################################################
# Test functions

runTest() {
    while true; do
        log "Running test $1"
        "$2"
        ec=$?
        cleanupCluster
        if [[ "$ec" != "0" ]]; then
            log "Error: test $1 failed... will wait 5 seconds and retry (ec=$ec)"
            sleep 5
        else
            log "Test $1 succeeded (ec=$ec)"
            break
        fi
    done
}

noMesh() {
    log "Testing without mesh"

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
EOF

    sleep 2

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "No Mesh"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

sidecars() {
    cat <<EOF >$TMPDIR/sidecarnohbone.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        ISTIO_META_ENABLE_HBONE: "false"
EOF

    log "Installing Istio"
    installIstio --set profile=default -f $TMPDIR/sidecarnohbone.yaml
    rm $TMPDIR/sidecarnohbone.yaml

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio-injection: enabled
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "Sidecars"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

sidecarsHBONE() {
    cat <<EOF >$TMPDIR/sidecarhbone.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        ISTIO_META_ENABLE_HBONE: "true"
EOF

    log "Installing Istio"
    installIstio --set profile=default -f $TMPDIR/sidecarhbone.yaml
    rm $TMPDIR/sidecarhbone.yaml

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio-injection: enabled
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "Sidecars w/ HBONE"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

ambient() {
    profile="ambient"
    if [[ "$K8S_TYPE" == "eks" ]]; then
        profile="ambient-aws"
    elif [[ "$K8S_TYPE" == "gke" ]]; then
        profile="ambient-gke"
    fi

    log "Installing Istio with profile: $profile"
    installIstio --set profile=$profile

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio.io/dataplane-mode: ambient
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "Ambient"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

ambientWithPEPs() {
    profile="ambient"
    if [[ "$K8S_TYPE" == "eks" ]]; then
        profile="ambient-aws"
    elif [[ "$K8S_TYPE" == "gke" ]]; then
        profile="ambient-gke"
    fi

    log "Installing Istio with profile: $profile"
    installIstio --set profile=$profile

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio.io/dataplane-mode: ambient
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    log "Generating PEP deployment"
    if [[ ! -z "$IMAGE_PULL_SECRET_NAME" ]]; then
        cat <<EOF >>$TMP/pep-prep.yaml
`envsubst < "$DIR/yaml/server-proxy.yaml"`
---
spec:
  template:
    spec:
      imagePullSecrets:
      - name: $IMAGE_PULL_SECRET_NAME
EOF
        cat $TMPDIR/pep-prep.yaml | yq eval-all '. as $item ireduce ({}; . * $item)' > $TMPDIR/pep.yaml
    else
        envsubst < "$DIR/yaml/server-proxy.yaml" >$TMPDIR/pep.yaml
    fi

    kctl apply -n $TESTING_NAMESPACE -f $TMPDIR/pep.yaml
    rm $TMPDIR/pep.yaml $TMPDIR/ips.yaml $TMPDIR/pep-prep.yaml || true

    kctl -n $TESTING_NAMESPACE wait pods -l ambient-type=pep --for condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: PEP deployment failed"
        return 1
    fi

    runPerfTest "Ambient w/ Server PEP"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

#########################################################################################################################

pushd "$AMBIENT_REPO_DIR" || exit

trap "trapCtrlC" 2

# Run the tests
# These are in loops as EKS has proven to be predictably unpredictable on if a test will actually complete..
# so on failure, clean up.. wait.. and just try again
runTest "No Mesh" noMesh
runTest "Sidecars" sidecars
runTest "Sidecars w/ HBONE" sidecarsHBONE
runTest "Ambient" ambient
runTest "Ambient w/ Server PEP" ambientWithPEPs

popd || exit

log "All tests completed, writing results"
writeResults

endTime=$(date +%s)
dt=$(echo "$endTime - $res1" | bc)
dd=$(echo "$dt/86400" | bc)
dt2=$(echo "$dt-86400*$dd" | bc)
dh=$(echo "$dt2/3600" | bc)
dt3=$(echo "$dt2-3600*$dh" | bc)
dm=$(echo "$dt3/60" | bc)
ds=$(echo "$dt3-60*$dm" | bc)

log `LC_NUMERIC=C printf "Total runtime: %d:%02d:%02d:%02.4f\n" $dd $dh $dm $ds`