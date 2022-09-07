# NOTE: This README has been updated specifically for the blog [here](https://www.solo.io/blog/what-istio-ambient-mesh-means-for-your-wallet/), checkout the `main` branch for a full list of features

# Performance Tests

This folder has scripts and resources that can execute performance tests to examine the performance of Istio Ambient and compare it to Istio sidecar and no-mesh setups.

For HTTP tests with [fortio](https://github.com/fortio/fortio), the script will execute a fortio client that will send requests to a [httpbin](https://github.com/postmanlabs/httpbin) service.

## Dependencies

* yq and jq are required

* Prometheus, Grafana and Node-Exporter are required for collecting metrics and veiwing the analysis dashboard:

```bash
cat <<\EOF > ./values.yaml
alertmanager:
  enabled: false
kubeStateMetrics:
  enabled: false
nodeExporter:
  enabled: true 
prometheus:
  prometheusSpec:
    retention: 60d
EOF

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
prometheus-community/kube-prometheus-stack \
--version 30.0.1 \
--namespace monitoring \
--create-namespace \
-f values.yaml
```

* `istioctl` is required for installing Istio during the tests. The demo istioctl binary should be downloaded and placed on in your `PATH`.  The binaries can be found [here](https://gcsweb.istio.io/gcs/istio-build/dev/0.0.0-ambient.191fe680b52c1754ee72a06b3e0d3f9d116f2e82)

* The Grafana dashboard can be viewed after importing the provided [json file](https://raw.githubusercontent.com/solo-io/ambient-performance/fortio-testing/dashboard/ambient-performance-analysis.json) via the web UI:

```bash
kubectl port-forward deployment/kube-prometheus-stack-grafana -n monitoring 3000
```

* Open [http://localhost:3000/dashboard/import](http://localhost:3000/dashboard/import) and then select to `Upload JSON file`

## Running with a config

You can now use provided sample `config.yaml` to configure your test parameters.  Users will need to add their kubectl cluster `context` to the provided file.

An example:

```yaml
service_port_name: "http"
params: "-c 1 -qps 2 -t 10m"
hub: "us-docker.pkg.dev/solo-io-ambient/istio"
tag: "1.16-dev"
perf_client: "fortio"
test_wait: "180"
server_scale: "10"
istioctl_path: "istioctl"
clusters:
- context: "<user_provided_context>"
```

The provided `config.yaml` will have fortio call httpbin-v1 for 10 minutes, httpbin-v2 for 10 minutes and finally httpbin-v3 for another 10. There are four test scenarios, each running about 30 minutes with 3 minutes rest between - so a little over 2 hours to complete.

The blog results were collected on a cluster with 3 nodes, each with 8 vCPU and 24GB memory.  Feel free to test different size clusters with different `-qps`, `-t` and `server_scale` parameters and check out the results!

If selecting a test duration that runs for less than 10 minutes for each scenario, the `_over_time` prometheus queries may need adjusting to produce cleaner graphs.

Then just run:

```sh
./run_tests.sh
```

## Config options

Some options can be defined globally, and/or in a cluster.  Globally will define defaults, with cluster overriding the default (if a cluster-level config option).

| Option | Can be defined in cluster | Default | Description |
| --- | --- | --- | --- |
| context | yes | N/A | The kubeconfig context to use. |
| continue_on_fail | no | yes | If yes, will continue to next cluster if a test fails. |
| hub | no | null | The hub to use for Istio. |
| params | yes | N/A | The parameters to pass to the performance client. |
| server_scale | yes | 1 | How many replicas to deploy, only used for http test types with the fortio performance client. |
| tag | no | null | The tag to use for Istio. |
| test_type | yes | http | The type of test to run. Valid values are: http, tcp, tcp-throughput |
| test_wait | yes | 1 | The amount of time, in seconds, to wait after a test completes before starting the next. |

The end of the test script will provide UTC timestamps for entering into the analysis dashboard so users can see a specific scenario or a comparison over the entire test run.

```bash
...
...
No Mesh
start:      2022-09-07 17:06:14
end:        2022-09-07 17:06:50
Sidecars
start:      2022-09-07 17:08:26
end:        2022-09-07 17:09:02
Ambient
start:      2022-09-07 17:11:06
end:        2022-09-07 17:11:42
Ambient w/ Waypoint Proxy
start:      2022-09-07 17:13:57
end:        2022-09-07 17:14:33
```
