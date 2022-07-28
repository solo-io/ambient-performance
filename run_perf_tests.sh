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

set -x

NIGHTHAWK_PARAMS="--concurrency 1 --output-format json --rps 200 --duration 60"
# NIGHTHAWK_PARAMS="--concurrency 1 --output-format json --max-requests-per-connection 1 --rps 200 --duration 60"
RESULTS_FILE="perf_tests_results_tcp.csv"
SERVICE_PORT_NAME="tcp-enforcment"

DIR="$( cd "$( dirname "$0" )" && pwd )"
RESULTS_FILE="$DIR/$RESULTS_FILE"
AMBIENT_REPO_DIR=$DIR/../istio-sidecarless

RESULTS_NAMES=()
RESULTS_P50=()
RESULTS_P90=()
RESULTS_P99=()
RESULTS_MAX=()

runPerfTest()
{
    echo "Executing performance tests for: $1.."
    RESULTS_NAMES+=("$1")
    eval kubectl exec deploy/nhclient -c nighthawk -- nighthawk_client "$NIGHTHAWK_PARAMS" http://nhserver:8080/ > "$DIR"/perf_test_results.json
    RESULTS_P50+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.5).duration)"' "$DIR"/perf_test_results.json | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P90+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.9).duration)"' "$DIR"/perf_test_results.json | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_P99+=("$(jq -r '.results[] | select(.name == "global") .statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.percentiles[]|select(.percentile == 0.990625).duration)"' "$DIR"/perf_test_results.json | sed 's/s//' | awk '{print $1*1000}')");
    RESULTS_MAX+=("$(jq -r '.results[].statistics[] | select(.id == "benchmark_http_client.latency_2xx") | "\(.max)"' "$DIR"/perf_test_results.json | sed 's/s//' | awk '{print $1*1000}')");
}

lockDownMutualTls() 
{
    kubectl apply -n istio-system -f - <<EOF
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
    sed "s/tcp-enforcment/$SERVICE_PORT_NAME/g" "$DIR"/perf-test.yaml | kubectl apply -f -
    kubectl wait pods -n default -l app=nhclient --for condition=Ready --timeout=90s
    kubectl wait pods -n default -l app=nhserver --for condition=Ready --timeout=90s
    sleep 5
}

noMesh()
{
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "No Mesh"

    # Cleanup before next test
    kubectl delete -f "$DIR"/perf-test.yaml
}

sidecars()
{
    # Setup Istio mesh
    go run istioctl/cmd/istioctl/main.go install -d manifests/ --set hub="$HUB" --set tag="$TAG" -y --set profile=default --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always
    lockDownMutualTls
    kubectl label namespace default istio-injection=enabled
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "With Istio Sidecars"

    # Cleanup before next test
    go run istioctl/cmd/istioctl/main.go x uninstall --purge -y
    kubectl delete -f "$DIR"/perf-test.yaml
    kubectl delete ns istio-system
    kubectl label namespace default istio-injection-
}

ambientNoPEPs()
{
    # Setup Ambient Mesh
    PROFILE="ambient"
    if [ "${K8S_TYPE}" == aws ]; then
        PROFILE="ambient-aws"
    elif [ "${K8S_TYPE}" == gcp ]; then
        PROFILE="ambient-gke"
    fi
    go run istioctl/cmd/istioctl/main.go install -d manifests/ --set hub="$HUB" --set tag="$TAG" -y --set profile=$PROFILE --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.defaultHttpRetryPolicy.attempts=0 --set values.global.imagePullPolicy=Always

    lockDownMutualTls
    deployPerfTestWorkloads

    # Run performance test and write results to file
    runPerfTest "Ambient (only uProxies)"
}

ambientWithPEPs()
{
    # Deploy PEP proxies (client and server)
    envsubst < "$DIR"/server-proxy.yaml | kubectl apply -f -
    envsubst < "$DIR"/client-proxy.yaml | kubectl apply -f -
    kubectl wait pods -n default -l ambient-type=pep --for condition=Ready --timeout=90s

    # Run performance test and write results to file
    runPerfTest "Ambient (uProxies + PEPs)"
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
    
    printf "\nMax," >> "$RESULTS_FILE"
    for ((i=0; i<${#RESULTS_NAMES[@]}; i++)); do printf "%s${RESULTS_MAX[$i]}," >> "$RESULTS_FILE"; done
}

pushd "$AMBIENT_REPO_DIR" || exit

noMesh
sidecars
ambientNoPEPs
ambientWithPEPs

popd || exit

writeResults

# Cleanup the cluster
# "$AMBIENT_REPO_DIR"/redirect.sh ambient clean
# kubectl delete -f .
# kubectl delete ns istio-system
