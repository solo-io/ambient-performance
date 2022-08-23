FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update -y && \
    apt upgrade -y && \
    apt install -y iperf3 jq datamash

COPY run.sh /run.sh

RUN chmod +x /run.sh
