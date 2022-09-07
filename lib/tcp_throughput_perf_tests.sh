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

# Setup some variable defaults, these should be read from the environment
startTime=$(date +%s)
DIR="$( cd "$( dirname "$0" )" && pwd )"

COUNT=${COUNT:-1000}

###############################################################################################################################
# Shared functions

runPerfTest() {
    test_name=$1

    if [[ "$2" == "skip" ]]; then
        log "Skipping test: $test_name"
        RESULTS_NAMES+=("$test_name")
        RESULTS_RECV_P50+=("Skipped")
        RESULTS_RECV_P90+=("Skipped")
        RESULTS_RECV_P95+=("Skipped")
        RESULTS_RECV_P99+=("Skipped")
        RESULTS_RECV_P999+=("Skipped")
        RESULTS_RECV_P9999+=("Skipped")
        RESULTS_RECV_MEAN+=("Skipped")
        RESULTS_RECV_STDDEV+=("Skipped")
        RESULTS_RECV_MAX+=("Skipped")
        RESULTS_RECV_MIN+=("Skipped")
        RESULTS_SEND_P50+=("Skipped")
        RESULTS_SEND_P90+=("Skipped")
        RESULTS_SEND_P95+=("Skipped")
        RESULTS_SEND_P99+=("Skipped")
        RESULTS_SEND_P999+=("Skipped")
        RESULTS_SEND_P9999+=("Skipped")
        RESULTS_SEND_MEAN+=("Skipped")
        RESULTS_SEND_STDDEV+=("Skipped")
        RESULTS_SEND_MAX+=("Skipped")
        RESULTS_SEND_MIN+=("Skipped")
        return 0
    fi

    log "Executing performance tests for: $test_name..."
    eval kctl exec -n $TESTING_NAMESPACE deploy/benchmark-client -- \
        env COUNT=$COUNT ./run-throughput.sh -c benchmark-server "$PARAMS" > "$RESULTS_JSON"
    if [[ $? -ne 0 ]]; then
        log "Error: iperf test failed"
        return 1
    fi

    RESULTS_NAMES+=("$test_name")
#    RESULTS_RECV_P50+=("$(jq -r '.receive.p50' "$RESULTS_JSON")");
#    RESULTS_RECV_P90+=("$(jq -r '.receive.p90' "$RESULTS_JSON")");
#    RESULTS_RECV_P95+=("$(jq -r '.receive.p95' "$RESULTS_JSON")");
#    RESULTS_RECV_P99+=("$(jq -r '.receive.p99' "$RESULTS_JSON")");
#    RESULTS_RECV_P999+=("NA");
#    RESULTS_RECV_P9999+=("NA");
#    RESULTS_RECV_MEAN+=("$(jq -r '.receive.mean' "$RESULTS_JSON")");
#    RESULTS_RECV_STDDEV+=("$(jq -r '.receive.stddev' "$RESULTS_JSON")");
#    RESULTS_RECV_MAX+=("$(jq -r '.receive.max' "$RESULTS_JSON")");
#    RESULTS_RECV_MIN+=("$(jq -r '.receive.min' "$RESULTS_JSON")");

    RESULTS_SEND_P50+=("$(jq -r '.send.p50' "$RESULTS_JSON")");
    RESULTS_SEND_P90+=("$(jq -r '.send.p90' "$RESULTS_JSON")");
    RESULTS_SEND_P95+=("$(jq -r '.send.p95' "$RESULTS_JSON")");
    RESULTS_SEND_P99+=("$(jq -r '.send.p99' "$RESULTS_JSON")");
    RESULTS_SEND_P999+=("NA");
    RESULTS_SEND_P9999+=("NA");
    RESULTS_SEND_MEAN+=("$(jq -r '.send.mean' "$RESULTS_JSON")");
    RESULTS_SEND_STDDEV+=("$(jq -r '.send.stddev' "$RESULTS_JSON")");
    RESULTS_SEND_MAX+=("$(jq -r '.send.max' "$RESULTS_JSON")");
    RESULTS_SEND_MIN+=("$(jq -r '.send.min' "$RESULTS_JSON")");

    rm "$RESULTS_JSON"
}

deployWorkloads() {
    log "Deploying workloads"
    kctl -n $TESTING_NAMESPACE apply -f "$DIR/../yaml/tcp-perf-test.yaml"
    log "Deployments applied to cluster, waiting for pods to be ready"
    sleep 5 # Can take time for the deployment to be known to the Kubernetes API
    kctl rollout status -n $TESTING_NAMESPACE deploy/benchmark-client
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_client pod failed to start"
        return 1
    fi
    kctl rollout status -n $TESTING_NAMESPACE deploy/benchmark-server
    if [[ $? -ne 0 ]]; then
        log "Error: nighthawk_server pod failed to start"
        return 1
    fi
    sleep 5
}

runTests() {
    runTest "No Mesh" noMesh
    runTest "Sidecars" sidecars
    #runTest "Sidecars w/ HBONE" sidecarsHBONE
    runPerfTest "Sidecars w/ HBONE" "skip"
    runTest "Ambient" ambient
    runTest "Ambient w/ Waypoint Proxy" ambientWithWPs
}


#########################################################################################################################

. $DIR/common.sh
