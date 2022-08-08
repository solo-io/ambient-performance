#!/bin/bash

RESULTS_FILE=${RESULTS_FILE:-perf_tests_results_tcp.csv}

echo "| Perc.  | No Mesh  | w/ Sidecar | Sidecar (HBONE)  | Ambient (no PEP) | Ambient (w/ PEP) |"
while IFS=, read -r perc nomesh sidecar sidecarhbone ambient pep
do
	printf "| %-6s | %-8s | %-10s | %-16s | %-16s | %-16s |\n" \
	    "$perc" "$nomesh" "$sidecar" "$sidecarhbone" "$ambient" "$pep"
done < <(tail -n 10 "$RESULTS_FILE")
