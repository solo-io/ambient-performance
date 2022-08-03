#!/bin/bash

RESULTS_FILE=${RESULTS_FILE:-perf_tests_results_tcp.csv}

echo "| Perc.  | No Mesh  | w/ Sidecar | Sidecar (HBONE)  | Linkerd    | Ambient (no PEP) | Ambient (w/ PEP) |"
while IFS=, read -r perc nomesh sidecar sidecarhbone linkerd ambient pep
do
	printf "| %-6s | %-8s | %-10s | %-16s | %-10s | %-16s | %-16s |\n" \
	    "$perc" "$nomesh" "$sidecar" "$sidecarhbone" "$linkerd" "$ambient" "$pep"
done < <(tail -n 6 "$RESULTS_FILE")
