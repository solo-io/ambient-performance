#!/bin/bash
# We pipe echos to stderr so that they will display in the pod's output and use stdout to pipe parseable data.

params=$@
count=${COUNT:-1000}

>&2 echo "Running iperf tests for $count iterations"
>&2 echo "params: $params"
>&2 echo ""

receive=()
send=()
i=0

while [ $i -lt $count ]; do
    test=$(timeout 20s iperf3 $params -J 2>/dev/null | jq -r 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        >&2 echo -n "!"
        continue
    fi
    >&2 echo -n "."
    #receive+=($(printf "%.4f" $(echo "$test" | jq -r '.end.sum_received.bits_per_second*0.0000001192')))
    rate=$(echo "$test" | jq -r '.end.sum_sent.bits_per_second*0.0000001192')
    if [[ $? -ne 0 || "$rate" == "0" ]]; then
        >&2 echo -n "%"
        continue
    fi
    send+=($(printf "%.4f" "$rate"))
    i=$((i+1))
done

>&2 echo ""
>&2 echo "Finished $i tests"

>&2 echo ""

avg_sent=$(printf "%.4f" $(echo "${send[@]}" | jq -s 'add / length'))
#avg_recv=$(printf "%.2f" $(echo "${receive[@]}" | jq -s 'add / length'))
mean_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash mean 1))
#mean_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash mean 1))
stddev_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash pstdev 1))
#stddev_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash pstdev 1))
min_sent=$(echo "${send[@]}" | jq -s 'min')
#min_recv=$(echo "${receive[@]}" | jq -s 'min')
max_sent=$(echo "${send[@]}" | jq -s 'max')
#max_recv=$(echo "${receive[@]}" | jq -s 'max')

p50_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash perc:50 1))
#p50_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash perc:50 1))
p90_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash perc:90 1))
#p90_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash perc:90 1))
p95_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash perc:95 1))
#p95_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash perc:95 1))
p99_sent=$(printf "%.4f" $(printf '%s\n' "${send[@]}" | datamash perc:99 1))
#p99_recv=$(printf "%.2f" $(printf '%s\n' "${receive[@]}" | datamash perc:99 1))

>&2 echo "Average: $(printf "%04.4fM %04.4fM" "$avg_sent" "$avg_recv")"
>&2 echo "Mean:    $(printf "%04.4fM %04.4fM" "$mean_sent" "$mean_recv")"
>&2 echo "Stddev:  $(printf "%04.4fM %04.4fM" "$stddev_sent" "$stddev_recv")"
>&2 echo "Min:     $(printf "%04.4fM %04.4fM" "$min_sent" "$min_recv")"
>&2 echo "Max:     $(printf "%04.4fM %04.4fM" "$max_sent" "$max_recv")"
>&2 echo "P50:     $(printf "%04.4fM %04.4fM" "$p50_sent" "$p50_recv")"
>&2 echo "P90:     $(printf "%04.4fM %04.4fM" "$p90_sent" "$p90_recv")"
>&2 echo "P95:     $(printf "%04.4fM %04.4fM" "$p95_sent" "$p95_recv")"
>&2 echo "P99:     $(printf "%04.4fM %04.4fM" "$p99_sent" "$p99_recv")"

# "receive": {
#     "avg": $avg_recv,
#     "mean": $mean_recv,
#     "stddev": $stddev_recv,
#     "min": $min_recv,
#     "max": $max_recv,
#     "p50": $p50_recv,
#     "p90": $p90_recv,
#     "p95": $p95_recv,
#     "p99": $p99_recv
# },

cat <<EOF
{
    "send": {
        "avg": $avg_sent,
        "mean": $mean_sent,
        "stddev": $stddev_sent,
        "min": $min_sent,
        "max": $max_sent,
        "p50": $p50_sent,
        "p90": $p90_sent,
        "p95": $p95_sent,
        "p99": $p99_sent
    }
}
EOF
