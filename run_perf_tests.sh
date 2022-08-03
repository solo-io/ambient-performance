#!/usr/bin/env bash

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

RESULTS_NAMES=()
RESULTS_P50=()
RESULTS_P90=()
RESULTS_P99=()
RESULTS_P999=()
RESULTS_P9999=()
RESULTS_MAX=()
runPerfTest()
{
    echo "Executing performance tests for: $1.."
    RESULTS_NAMES+=("$1")
    eval kubectl $CONTEXT exec deploy/nhclient -c nighthawk -- nighthawk_client "$NIGHTHAWK_PARAMS" http://nhserver:8080/ > "$RESULTS_JSON"
    if [[ $? -ne 0 ]]; then
        echo "Failed to execute nighthawk_client"
        echo "More information can be found in $RESULTS_JSON"
        cleanup_cluster
        exit 1
    fi
    RESULTS_P50+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.5).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P90+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P99+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.990625).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P9999+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.99990234375).duration)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MAX+=("$(jq -r '.results[].statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.max)"' "$RESULTS_JSON" | sed 's/s//' | awk '{print $1*1000}')");

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

deployPerfTestWorkloads()
{
    sed "s/tcp-enforcment/$SERVICE_PORT_NAME/g" "$DIR"/yaml/perf-test.yaml | kubectl $CONTEXT apply -f -
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for condition=Ready --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for condition=Ready --timeout=90s
    sleep 5
}

noMesh()
{
    echo ""

    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "No Mesh"

    # Cleanup before next test
    kubectl $CONTEXT delete -f "$DIR"/yaml/perf-test.yaml

    # Wait for them to be deleted
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for=delete --timeout=90s
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
    go run istioctl/cmd/istioctl/main.go install $CONTEXT -d manifests/ --set hub="$HUB" --set tag="$TAG" -y --set profile=default -f /tmp/sidecarnohbone.yaml --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always

    rm /tmp/sidecarnohbone.yaml

    lockDownMutualTls
    kubectl $CONTEXT label namespace default istio-injection=enabled
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "With Istio Sidecars"

    # Cleanup before next test
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT
    kubectl $CONTEXT delete -f "$DIR"/yaml/perf-test.yaml
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for=delete --timeout=90s
    kubectl $CONTEXT delete ns istio-system
    kubectl $CONTEXT label namespace default istio-injection-
}

sidecarsWithHBONE()
{
    echo ""

    # Setup Istio mesh
    go run istioctl/cmd/istioctl/main.go install $CONTEXT -d manifests/ --set hub="$HUB" --set tag="$TAG" -y --set profile=default --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always
    lockDownMutualTls
    kubectl $CONTEXT label namespace default istio-injection=enabled
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "With Istio Sidecars (HBONE)"

    # Cleanup before next test
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y $CONTEXT
    kubectl $CONTEXT delete -f "$DIR"/yaml/perf-test.yaml
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for=delete --timeout=90s
    kubectl $CONTEXT delete ns istio-system
    kubectl $CONTEXT label namespace default istio-injection-
}

linkerdTest()
{
    if [[ -z "$LINKERD" ]]; then
        RESULTS_NAMES+=("Linkerd")
        RESULTS_P50+=("Skipped")
        RESULTS_P90+=("Skipped")
        RESULTS_P99+=("Skipped")
        RESULTS_P999+=("Skipped")
        RESULTS_P9999+=("Skipped")
        RESULTS_MAX+=("Skipped")
        return 0
    fi

    echo ""
    if [[ $K8S_TYPE == "aws" ]]; then
        linkerd $CONTEXT install --set proxyInit.runAsRoot=true | kubectl $CONTEXT apply -f -
    else
        linkerd $CONTEXT install --set proxyInit.runAsRoot=true | kubectl $CONTEXT apply -f -
    fi
    linkerd $CONTEXT check

    sed "s/tcp-enforcment/$SERVICE_PORT_NAME/g" "$DIR"/yaml/perf-test.yaml | linkerd $CONTEXT inject - | kubectl $CONTEXT apply -f -
    sleep 3
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for condition=Ready --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for condition=Ready --timeout=90s
    sleep 5

    runPerfTest "Linkerd"

    # Cleanup before next test
    kubectl $CONTEXT delete -f "$DIR"/yaml/perf-test.yaml

    # Wait for them to be deleted
    kubectl $CONTEXT wait pods -n default -l app=nhclient --for=delete --timeout=90s
    kubectl $CONTEXT wait pods -n default -l app=nhserver --for=delete --timeout=90s

    linkerd $CONTEXT uninstall | kubectl $CONTEXT delete -f -
    sleep 15
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
    go run istioctl/cmd/istioctl/main.go install $CONTEXT -d manifests/ --set hub="$HUB" --set tag="$TAG" -y --set profile=$PROFILE --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always

    lockDownMutualTls
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "Ambient (only uProxies)"
}

ambientWithPEPs()
{
    echo ""

    # Deploy PEP proxies (client and server)
    envsubst < "$DIR"/yaml/server-proxy.yaml | kubectl $CONTEXT apply -f -
    envsubst < "$DIR"/yaml/client-proxy.yaml | kubectl $CONTEXT apply -f -
    kubectl $CONTEXT wait pods -n default -l ambient-type=pep --for condition=Ready --timeout=120s
    if [[ $? != "0" ]]; then
        echo "Failed to deploy PEP proxies... exiting dirty for log review"
        exit 1
    fi
    sleep 10
    kubectl $CONTEXT get pod -A

    # Run performance test and write results to file
    runPerfTest "Ambient (uProxies + PEPs)"

    # Clean up proxies
    kubectl $CONTEXT delete -f "$DIR"/yaml/server-proxy.yaml -f "$DIR"/yaml/client-proxy.yaml -f "$DIR"/yaml/perf-test.yaml
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
    kubectl $CONTEXT label ns default istio-injection- || true
    kubectl $CONTEXT label ns default istio.io/dataplane-mode- || true
}

trap_ctrlc() {
    echo "CTRL+C received. Cleaning up cluster"
    cleanup_cluster
    echo "Exiting..."
    exit 2
}

pushd "$AMBIENT_REPO_DIR" || exit

trap "trap_ctrlc" 2

noMesh
sidecars
sidecarsWithHBONE
linkerdTest
# Label namespace, as the CNI relies on this label
kubectl $CONTEXT label ns default istio.io/dataplane-mode=ambient --overwrite
ambientNoPEPs
ambientWithPEPs

# Clean up cluster
cleanup_cluster

popd || exit

writeResults
