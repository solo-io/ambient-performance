#!/bin/bash

echo "" >> perf_tests_results_tcp.csv

echo "| Perc.  | No Mesh  | w/ Sidecar | Linkerd    | Ambient (no PEP) | Ambient (w/ PEP) |"
while IFS=, read -r perc nomesh sidecar linkerd ambient pep
do
	printf "| %-6s | %-8s | %-10s | %-10s | %-16s | %-16s |\n" "$perc" "$nomesh" "$sidecar" "$linkerd" "$ambient" "$pep"
done < <(tail -n 6 perf_tests_results_tcp.csv)
