FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update -y && \
    apt upgrade -y && \
    apt install -y iperf3 jq datamash

COPY run-latency.sh /run-latency.sh
RUN chmod +x /run-latency.sh
COPY run-throughput.sh /run-throughput.sh
RUN chmod +x /run-throughput.sh
