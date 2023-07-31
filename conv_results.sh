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

RESULTS_FILE=${RESULTS_FILE:-perf_tests_results_tcp.csv}

echo "| Perc.  | No Mesh  | w/ Sidecar | Ambient          | Ambient (w/ Waypoint Proxy) |"
while IFS=, read -r perc nomesh sidecar ambient waypointproxy
do
	printf "| %-6s | %-8s | %-10s | %-16s | %-27s |\n" \
	    "$perc" "$nomesh" "$sidecar" "$ambient" "$waypointproxy"
done < <(tail -n 10 "$RESULTS_FILE")
