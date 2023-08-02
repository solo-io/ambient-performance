FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update -y && \
    apt upgrade -y && \
    apt install -y jq curl

RUN curl -L https://github.com/fortio/fortio/releases/download/v1.57.4/fortio-linux_amd64-1.57.4.tgz \
 | tar -C / -xvzpf -

COPY run-latency.sh /run-latency.sh
RUN chmod +x /run-latency.sh
