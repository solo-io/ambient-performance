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

#########################################################################################################################
# Test functions

noMesh() {
    log "Testing without mesh"

    log "Creating testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
EOF

    sleep 2

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "No Mesh"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

sidecars() {
    cat <<EOF >$TMPDIR/sidecarnohbone.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        ISTIO_META_ENABLE_HBONE: "false"
EOF

    log "Installing Istio"
    installIstio --set profile=default -f $TMPDIR/sidecarnohbone.yaml
    rm $TMPDIR/sidecarnohbone.yaml

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio-injection: enabled
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "Sidecars"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

ambient() {
    profile="ambient"

    log "Installing Istio with profile: $profile"
    installIstio --set profile=$profile

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio.io/dataplane-mode: ambient
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    runPerfTest "Ambient"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}

ambientWithWPs() {
    profile="ambient"

    log "Installing Istio with profile: $profile"
    installIstio --set profile=$profile

    applyMutualTLS

    log "Creating and labeling testing namespace"
    cat <<EOF | kctl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $TESTING_NAMESPACE
  labels:
    istio.io/dataplane-mode: ambient
EOF
    sleep 2

    applyImagePullSecret $TESTING_NAMESPACE

    deployWorkloads
    if [[ $? -ne 0 ]]; then
        log "Error: deployment failed"
        return 1
    fi

    log "Applying Waypoint Proxy"
    if [[ ! -z "$1" ]]; then
        kctl apply -n $TESTING_NAMESPACE -f "$DIR/../yaml/$1"
    else
        runIstioctl x waypoint apply -n $TESTING_NAMESPACE --service-account=benchmark-server
    fi

    sleep 10

    kctl -n $TESTING_NAMESPACE wait pods -l gateway.istio.io/managed=istio.io-mesh-controller --for condition=Ready --timeout=120s
    if [[ $? -ne 0 ]]; then
        log "Error: Waypoint Proxy deployment failed"
        return 1
    fi

    runPerfTest "Ambient w/ Waypoint Proxy"
    if [[ $? -ne 0 ]]; then
        log "Error: testing failed"
        return 1
    fi

    return 0
}
