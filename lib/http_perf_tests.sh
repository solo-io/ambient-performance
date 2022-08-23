#!/bin/bash

# Setup some variable defaults, these should be read from the environment
startTime=$(date +%s)
DIR="$( cd "$( dirname "$0" )" && pwd )"

###############################################################################################################################
# Shared functions

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
        nighthawk_client "$NIGHTHAWK_PARAMS" http://benchmark-server:8080/ > "$RESULTS_JSON"
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

deployWorkloads() {
    log "Deploying workloads"
    sed "s/tcp-enforcement/$SERVICE_PORT_NAME/g" "$DIR/../yaml/http-perf-test.yaml" | kctl -n $TESTING_NAMESPACE apply -f -
    log "Deployments applied to cluster, waiting for pods to be ready"
    sleep 5 # Can take time for the deployment to be known to the Kubernetes API
    kctl wait pods -n $TESTING_NAMESPACE -l app=benchmark-client --for=condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_client pod failed to start"
        return 1
    fi
    kctl wait pods -n $TESTING_NAMESPACE -l app=benchmark-server --for=condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_server pod failed to start"
        return 1
    fi
    sleep 5
}

runTests() {
    runTest "No Mesh" noMesh
    runTest "Sidecars" sidecars
    runTest "Sidecars w/ HBONE" sidecarsHBONE
    runTest "Ambient" ambient
    runTest "Ambient w/ Server PEP" ambientWithPEPs
}


#########################################################################################################################

. $DIR/common.sh
