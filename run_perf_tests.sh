#!/bin/bash

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

####################################################################################################
# This has been replaced by perf_tests.sh
####################################################################################################

set -x

DIR="$( cd "$( dirname "$0" )" && pwd )"

NIGHTHAWK_PARAMS=${NIGHTHAWK_PARAMS:-"--concurrency 1 --output-format json --rps 200 --duration 60"}
# NIGHTHAWK_PARAMS="--concurrency 1 --output-format json --max-requests-per-connection 1 --rps 200 --duration 60"
SERVICE_PORT_NAME=${SERVICE_PORT_NAME:-"tcp-enforcment"}
AMBIENT_REPO_DIR=${AMBIENT_REPO_DIR:-"$DIR/../istio-sidecarless"}
DATERUN=$(date +"%Y%m%d-%H%M")
RESULTS_JSON=${RESULTS_JSON:-"/tmp/results-$DATERUN.json"}
RESULTS_FILE=${RESULTS_FILE:-"$DIR/results/results-$DATERUN.csv"}
if [[ ! -z "$CONTEXT" ]]; then
    CONTEXT="--context $CONTEXT"
fi

if [[ ! -d "results" ]]; then
    mkdir "results"
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
TESTING_NAMESPACE="test-$DATERUN"

RESULTS_NAMES=()
RESULTS_P50=()
RESULTS_P90=()
RESULTS_P99=()
RESULTS_P999=()
RESULTS_P9999=()
RESULTS_MAX=()
runPerfTest()
{
    # let things settle down before we test.
    sleep 10
    echo ""
    echo "Executing performance tests for: $1.."
    RESULTS_NAMES+=("$1")
    eval kubectl $CONTEXT exec -n $TESTING_NAMESPACE deploy/nhclient -c nighthawk -- nighthawk_client "$NIGHTHAWK_PARAMS" http://nhserver:8080/ > "$RESULTS_JSON"
    if [[ $? -ne 0 ]]; then
        echo "Test failed."
        #cleanup_cluster
        exit 1
    fi

    RESULTS_P50+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.5).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P90+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P99+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.990625).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P9999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.99990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MAX+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.max)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");

    rm "$RESULTS_JSON"
}

lockDownMutualTls() 
{
    kubectl $CONTEXT apply -n istio-system -f - <<EOF
        apiVersion: security.istio.io/v1beta1
        kind: PeerAuthentication
        metadata:
            name: "default"
        spec:
            mtls:
                mode: STRICT
EOF
}

installIstio()
{
    secret=""
    if [[ "$IMAGE_PULL_SECRET_NAME" != "" ]]; then
        cat <<EOF >/tmp/imagepullsecrets.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      imagePullSecrets:
        - $IMAGE_PULL_SECRET_NAME
EOF
      secret="-f /tmp/imagepullsecrets.yaml "
    fi
    kubectl $CONTEXT create ns istio-system
    kubectl $CONTEXT apply -n istio-system -f $IMAGE_PULL_SECRET
    go run istioctl/cmd/istioctl/main.go install $CONTEXT -d manifests/ --set hub="$HUB" --set tag="$TAG" -y $@ $secret
    if [[ $? != "0" ]]; then
        echo "Failed to install Istio"
        cleanup_cluster
        exit 1
    fi
    if [[ "$IMAGE_PULL_SECRET_NAME" != "" ]]; then
        rm /tmp/imagepullsecrets.yaml
    fi
}

deployPerfTestWorkloads()
{
    sed "s/tcp-enforcment/$SERVICE_PORT_NAME/g" "$DIR"/yaml/perf-test.yaml | kubectl $CONTEXT -n $TESTING_NAMESPACE apply -f -
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhclient --for condition=Ready --timeout=90s
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhserver --for condition=Ready --timeout=90s
    sleep 5
}

noMesh()
{
    echo ""

    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "No Mesh"

    # Cleanup before next test
    kubectl $CONTEXT delete -n $TESTING_NAMESPACE -f "$DIR"/yaml/perf-test.yaml

    # Wait for them to be deleted
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhserver --for=delete --timeout=90s
}

sidecars()
{
    echo ""

    cat <<EOF >/tmp/sidecarnohbone.yaml
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

    # Setup Istio mesh
    installIstio --set profile=default -f /tmp/sidecarnohbone.yaml --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always

    rm /tmp/sidecarnohbone.yaml

    lockDownMutualTls
    kubectl $CONTEXT label namespace $TESTING_NAMESPACE istio-injection=enabled
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "With Istio Sidecars"

    # Cleanup before next test
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT
    kubectl $CONTEXT delete -n $TESTING_NAMESPACE -f "$DIR"/yaml/perf-test.yaml
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhserver --for=delete --timeout=90s
    kubectl $CONTEXT delete ns istio-system
    kubectl $CONTEXT label namespace $TESTING_NAMESPACE istio-injection-
}

sidecarsWithHBONE()
{
    echo ""

    cat <<EOF >/tmp/sidecarhbone.yaml
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

    # Setup Istio mesh
    installIstio -f /tmp/sidecarhbone.yaml --set profile=default --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always
    if [[ $? != "0" ]]; then
        echo "Failed to install istio"
        exit 1
    fi

    rm /tmp/sidecarhbone.yaml

    lockDownMutualTls
    kubectl $CONTEXT label namespace $TESTING_NAMESPACE istio-injection=enabled
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "With Istio Sidecars (HBONE)"

    # Cleanup before next test
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT
    kubectl $CONTEXT delete -n $TESTING_NAMESPACE -f "$DIR"/yaml/perf-test.yaml
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l app=nhserver --for=delete --timeout=90s
    kubectl $CONTEXT delete ns istio-system
    kubectl $CONTEXT label namespace $TESTING_NAMESPACE istio-injection-
}

prepAmbientTest() {
    installIstio --set profile=$PROFILE --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always

    if [[ $? != "0" ]]; then
        echo "Failed to install istio"
        exit 1
    fi

    lockDownMutualTls
    deployPerfTestWorkloads
}

ambientNoPEPs()
{
    echo ""

    # Setup Ambient Mesh
    PROFILE="ambient"
    if [ "${K8S_TYPE}" == aws ]; then
        PROFILE="ambient-aws"
    elif [ "${K8S_TYPE}" == gcp ]; then
        PROFILE="ambient-gke"
    fi

    prepAmbientTest

    kubectl get pod -A

    # Run performance test and write results to file
    runPerfTest "Ambient (only uProxies)"
}

ambientWithPEPs()
{
    echo ""

    prepAmbientTest

    touch /tmp/imagepullsecrets.yaml
    if [[ ! -z "$IMAGE_PULL_SECRET_NAME" ]]; then
        cat <<EOF >/tmp/imagepullsecrets.yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ${IMAGE_PULL_SECRET_NAME}
EOF
    fi 
    set -x
    # Deploy PEP proxies (client and server)
    # This shouldn't be necessary, but yq seems to break here if we pass files as an argument in this script... why??
    cat <<EOF >/tmp/pep-prep.yaml
`envsubst < "$DIR"/yaml/server-proxy.yaml`
---
`cat "/tmp/imagepullsecrets.yaml"`
EOF
    cat /tmp/pep-prep.yaml | yq eval-all '. as $item ireduce ({}; . * $item)' > /tmp/pep.yaml
    if [[ $? -ne "0" ]]; then
      exit 1
    fi
    kubectl $CONTEXT apply -n $TESTING_NAMESPACE -f /tmp/pep.yaml
    #    envsubst < "$DIR"/yaml/client-proxy.yaml | kubectl $CONTEXT apply -f -

    sleep 5

    kubectl $CONTEXT wait pods -n $TESTING_NAMESPACE -l ambient-type=pep --for condition=Ready --timeout=120s
    if [[ $? != "0" ]]; then
        echo "Failed to deploy PEP."
        cleanup_cluster
        exit 1
    fi
    sleep 10
    kubectl $CONTEXT get pod -A


    # Run performance test and write results to file
    runPerfTest "Ambient (uProxies + PEPs)"

    # Clean up proxies
    kubectl $CONTEXT delete -n $TESTING_NAMESPACE -f "$DIR"/yaml/server-proxy.yaml -f "$DIR"/yaml/client-proxy.yaml -f "$DIR"/yaml/perf-test.yaml
}

writeResults()
{
    echo "Run time: $(date)" > "$RESULTS_FILE"
    echo "Nighthawk client parameters: $NIGHTHAWK_PARAMS" >> "$RESULTS_FILE"
    echo "Service port name: $SERVICE_PORT_NAME" >> "$RESULTS_FILE"

    printf "\n," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_NAMES[$i]}," >> "$RESULTS_FILE"; done

    printf "\np50," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P50[$i]}," >> "$RESULTS_FILE"; done

    printf "\np90," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P90[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P99[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.9," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P999[$i]}," >> "$RESULTS_FILE"; done

    printf "\np99.99," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_P9999[$i]}," >> "$RESULTS_FILE"; done

    printf "\nMax," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_MAX[$i]}," >> "$RESULTS_FILE"; done

    printf "\n" >> "$RESULTS_FILE"
}

cleanup_cluster() {
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT || true
    kubectl $CONTEXT delete -f "$DIR"/yaml/perf-test.yaml -f "$DIR"/yaml/client-proxy.yaml -f "$DIR"/yaml/server-proxy.yaml || true
    kubectl $CONTEXT delete ns istio-system || true
    kubectl $CONTEXT delete ns $TESTING_NAMESPACE || true
    kubectl $CONTEXT label ns $TESTING_NAMESPACE istio-injection- || true
    kubectl $CONTEXT label ns $TESTING_NAMESPACE istio.io/dataplane-mode- || true
}

trap_ctrlc() {
    echo "CTRL+C received. Cleaning up cluster"
    cleanup_cluster
    echo "Exiting..."
    exit 2
}

pushd "$AMBIENT_REPO_DIR" || exit

trap "trap_ctrlc" 2

kubectl create ns $TESTING_NAMESPACE
# Apply image pull secret, if set, to kube-system and default, we handle istio's ns during install
# This is useful for our GAR-stored images being deployed to an EKS cluster
if [[ ! -z "$IMAGE_PULL_SECRET" ]]; then
    kubectl $CONTEXT apply -n kube-system -f $IMAGE_PULL_SECRET
    kubectl $CONTEXT apply -n $TESTING_NAMESPACE -f $IMAGE_PULL_SECRET
fi

noMesh
sidecars
sidecarsWithHBONE
# Linkerd test removed as I do not know enough about it to ensure the configuration is comparable to sidecars
# for compariable and fair testing.
#linkerdTest
# Label namespace, as the CNI relies on this label
kubectl $CONTEXT label ns $TESTING_NAMESPACE istio.io/dataplane-mode=ambient --overwrite
ambientNoPEPs
ambientWithPEPs

# Clean up cluster
cleanup_cluster

popd || exit

writeResults
