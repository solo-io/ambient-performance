
#########################################################################################################################
# Test functions

noMesh() {
    log "Testing without mesh"

    log "Creating and labeling testing namespace"
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

sidecarsHBONE() {
    cat <<EOF >$TMPDIR/sidecarhbone.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        ISTIO_META_ENABLE_HBONE: "true"
EOF

    log "Installing Istio"
    installIstio --set profile=default -f $TMPDIR/sidecarhbone.yaml
    rm $TMPDIR/sidecarhbone.yaml

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

    runPerfTest "Sidecars w/ HBONE"
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
    wp="$DIR/../yaml/waypointproxy.yaml"
    if [[ ! -z "$1" ]]; then
        wp="$DIR/../yaml/$1"
    fi

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
    kctl apply -n $TESTING_NAMESPACE -f "$wp"

    sleep 10

    kctl -n $TESTING_NAMESPACE wait pods -l ambient-type=waypoint --for condition=Ready --timeout=120s
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
