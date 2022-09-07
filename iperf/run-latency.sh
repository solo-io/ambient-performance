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

>&2 echo "Running iperf tests for $count iterations"
>&2 echo "params: $params"
>&2 echo ""

timings=()
i=0

while [ $i -lt $count ]; do
    test=$(timeout 5s iperf3 $params -J | jq '[.intervals[0].streams[].seconds*1000] | add')
    if [[ $? -ne 0 ]]; then
        >&2 echo -n "!"
        continue
    fi
    >&2 echo -n "."
    timings+=($(printf "%.4f" "$test"))
    i=$((i+1))
done

>&2 echo ""
>&2 echo "Finished $i tests"

>&2 echo ""

>&2 echo "Average: $(printf "%.4f" $(echo "${timings[@]}" | jq -s 'add / length'))"
>&2 echo "Mean: $(printf "%.4f" $(printf '%s\n' "${timings[@]}" | datamash mean 1))"
>&2 echo "StdDev: $(printf "%.4f" $(printf '%s\n' "${timings[@]}" | datamash pstdev 1))"
>&2 echo "Min: $(echo "${timings[@]}" | jq -s 'min')"
>&2 echo "Max: $(echo "${timings[@]}" | jq -s 'max')"
>&2 echo "50th percentile: $(printf '%s\n' "${timings[@]}" | datamash perc:50 1)"
>&2 echo "90th percentile: $(printf '%s\n' "${timings[@]}" | datamash perc:90 1)"
>&2 echo "95th percentile: $(printf '%s\n' "${timings[@]}" | datamash perc:95 1)"
>&2 echo "99th percentile: $(printf '%s\n' "${timings[@]}" | datamash perc:99 1)"

cat <<EOF
{
    "average": $(printf "%.4f" $(echo "${timings[@]}" | jq -s 'add / length')),
    "mean": $(printf "%.4f" $(printf '%s\n' "${timings[@]}" | datamash mean 1)),
    "stddev": $(printf "%.4f" $(printf '%s\n' "${timings[@]}" | datamash pstdev 1)),
    "min": $(echo "${timings[@]}" | jq -s 'min'),
    "max": $(echo "${timings[@]}" | jq -s 'max'),
    "p50": $(printf '%s\n' "${timings[@]}" | datamash perc:50 1),
    "p90": $(printf '%s\n' "${timings[@]}" | datamash perc:90 1),
    "p95": $(printf '%s\n' "${timings[@]}" | datamash perc:95 1),
    "p99": $(printf '%s\n' "${timings[@]}" | datamash perc:99 1)
}
EOF
