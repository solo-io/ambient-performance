#!/bin/bash

set -ex

HUB=${HUB:-us-west3-docker.pkg.dev/solo-test-236622/daniel-solo}
IMAGE=${IMAGE:-iperf3}
TAG=${TAG:-latest}

if [[ ! -z "$HUB" ]]; then
    HUB="$HUB/"
fi

docker build -t $HUB$IMAGE:$TAG .
docker push $HUB$IMAGE:$TAG