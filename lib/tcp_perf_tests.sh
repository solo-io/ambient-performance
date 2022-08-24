#!/bin/bash

DIR="$( cd "$( dirname "$0" )" && pwd )"

echo "Test: $TEST_TYPE"

if [[ "$TEST_TYPE" == "tcp-throughput" ]]; then
    echo "Loading throughput tests"
    . "$DIR/tcp_throughput_perf_tests.sh"
else
    echo "Loading latency tests"
    . "$DIR/tcp_latency_perf_tests.sh"
fi
