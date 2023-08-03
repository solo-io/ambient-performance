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

# We pipe echos to stderr so that they will display in the pod's output and use stdout to pipe parseable data.

params=$@
count=${COUNT:-1000}
RESULTS_JSON="results.json"

>&2 echo "Running fortio load test"
>&2 echo "Params: $params"
>&2 echo ""

timings=()
i=0

eval fortio load $params -n $count -json $RESULTS_JSON -p "50,90,95,99,99.9,99.99" tcp://benchmark-server:8078

if [[ $? -ne 0 ]]; then
    log "Error: fortio load call failed"
    return 1
fi

RESULTS_NAMES+=("$test_name")
RESULTS_P50+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 50) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_P90+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 90) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_P95+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 95) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_P99+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 99) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_P999+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 99.9) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_P9999+=("$(jq -r '.DurationHistogram.Percentiles[] | select(.Percentile == 99.99) | .Value' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_MEAN+=("$(jq -r '.DurationHistogram.Avg' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_STDDEV+=("$(jq -r '.DurationHistogram.StdDev' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_MAX+=("$(jq -r '.DurationHistogram.Max' $RESULTS_JSON | awk '{print $1*1000}')");
RESULTS_MIN+=("$(jq -r '.DurationHistogram.Min' $RESULTS_JSON | awk '{print $1*1000}')");
rm "$RESULTS_JSON"

>&2 echo ""
>&2 echo "Finished latency test"

>&2 echo ""

>&2 echo "Mean: $(printf "%.4f" $RESULTS_MEAN)"
>&2 echo "StdDev: $(printf "%.4f" $RESULTS_STDDEV)"
>&2 echo "Min: $(printf "%.4f" $RESULTS_MIN)"
>&2 echo "Max: $(printf "%.4f" $RESULTS_MAX)"
>&2 echo "50th percentile: $(printf "%.4f" $RESULTS_P50)"
>&2 echo "90th percentile: $(printf "%.4f" $RESULTS_P90)"
>&2 echo "95th percentile: $(printf "%.4f" $RESULTS_P95)"
>&2 echo "99th percentile: $(printf "%.4f" $RESULTS_P99)"
>&2 echo "99.9th percentile: $(printf "%.4f" $RESULTS_P999)"
>&2 echo "99.99th percentile: $(printf "%.4f" $RESULTS_P9999)"

cat <<EOF
{
    "mean": $(printf "%.4f" $RESULTS_MEAN),
    "stddev": $(printf "%.4f" $RESULTS_STDDEV),
    "min": $(printf "%.4f" $RESULTS_MIN),
    "max": $(printf "%.4f" $RESULTS_MAX),
    "p50": $(printf "%.4f" $RESULTS_P50),
    "p90": $(printf "%.4f" $RESULTS_P90),
    "p95": $(printf "%.4f" $RESULTS_P95),
    "p99": $(printf "%.4f" $RESULTS_P99),
    "p999": $(printf "%.4f" $RESULTS_P999),
    "p9999": $(printf "%.4f" $RESULTS_P9999)
}
EOF
