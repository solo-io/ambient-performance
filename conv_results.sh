#!/bin/bash

RESULTS_FILE=${RESULTS_FILE:-perf_tests_results_tcp.csv}

echo "| Perc.  | No Mesh  | w/ Sidecar | Sidecar (HBONE)  | Ambient          | Ambient (w/ Waypoint Proxy) |"
while IFS=, read -r perc nomesh sidecar sidecarhbone ambient waypointproxy
do
	printf "| %-6s | %-8s | %-10s | %-16s | %-16s | %-28s |\n" \
	    "$perc" "$nomesh" "$sidecar" "$sidecarhbone" "$ambient" "$waypointproxy"
done < <(tail -n 10 "$RESULTS_FILE")
