# Performance Tests

This folder has scripts and resources that can execute performance tests to examine the performance of Istio Ambient and compare it to Istio sidecar and no-mesh setups.

For HTTP tests with [nighthawk](https://github.com/envoyproxy/nighthawk), the script will execute a nighthawk client that will send requests to the server service which is also a nighthawk running in a server mode.

For HTTP tests with [fortio](https://github.com/fortio/fortio), the script will execute a fortio client that will send requests to a [httpbin](https://github.com/postmanlabs/httpbin) service.

For TCP tests, the script will execute an [iperf3](https://iperf.fr) client that will send requests to an iperf3 server for a given number
of connections, defaulting to 1000.

## Dependencies

* yq and jq are required

* The performance test script in this project are executing redirection scripts and Istio installation from the [Istio Sidecarless](https://github.com/solo-io/istio-sidecarless) repo

## Running with a config

To allow chaining multiple clusters with the same config, a number of changes have been made.

You can now use config.yaml to configure your test parameters.

Valid test types:
- http
- tcp
- tcp-throughput

For http test types, there are two possible performance clients:
- nighthawk
- fortio

An example:

```yaml
service_port_name: "tcp"
params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 1 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
final_result: "/home/daniel/results/test.txt"
test_type: "http"
perf_client: "nighthawk"
istioctl_path: "/home/daniel/dev/ambient/istioctl"
clusters:
- context: "gke_solo-test-236622_us-west1-c_daniel-ambient"
  result_file: "/home/daniel/results/http/1.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 1 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
```

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
| count | yes | 1000 | How many times to run the test. Only used for tcp test_type. |
| final_result | no | /tmp/results.txt | The file to write the final results (ASCII table) to. |
| hub | no | null | The hub to use for Istio. |
| params | yes | N/A | The parameters to pass to the performance client. |
| perf_client | yes | nighthawk | The performance client to use. Only used for http test_type. Valid values are: nighthawk, fortio |
| result_file | yes | /tmp/results.csv | The file to write test results to, *only* a cluster level config item. |
| server_scale | yes | 1 | How many replicas to deploy, only used for http test types with the fortio performance client. |
| tag | no | null | The tag to use for Istio. |
| test_type | yes | http | The type of test to run. Valid values are: http, tcp, tcp-throughput |
| test_wait | yes | 1 | The amount of time, in seconds, to wait after a test completes before starting the next. |

### Example Configs

```yaml
service_port_name: "tcp"
params: '-n 100M --parallel 1 --bidir'
final_result: "/home/daniel/results/testt.txt"
hub: "us-docker.pkg.dev/solo-io-ambient/istio"
tag: "1.16-dev"
test_type: "tcp-throughput"
count: 1000
clusters:
- context: "gke_solo-test-236622_us-west1-c_daniel-ambient"
  result_file: "/home/daniel/results/test-throughput.csv"
  params: '-n 100M'
- context: "gke_solo-test-236622_us-west1-c_daniel-ambient"
  test_type: "tcp"
  result_file: "/home/daniel/results/test-latency.csv"
  params: '-n 1K --parallel 1 --bidir'
```

```yaml
params: '--concurrency 1 --simple-warmup --output-format json --rps 200 --duration 60'
final_result: "/home/daniel/results/overall-gke.txt"
hub: "us-docker.pkg.dev/solo-io-ambient/istio"
tag: "1.16-dev"
test_type: "http"
context: "gke_solo-test-236622_us-west1-c_daniel-ambient"
clusters:
- result_file: "/home/daniel/results/http/1.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 1 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/2.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 2 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/8.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 8 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/16.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 16 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/32.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 32 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/64.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 64 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
- result_file: "/home/daniel/results/http/128.csv"
  params: '--concurrency 2 --output-format json --prefetch-connections --open-loop --experimental-h1-connection-reuse-strategy lru --connections 128 --rps 1000 --duration 60 --request-header "x-nighthawk-test-server-config: {response_body_size:1024}" --request-body-size 1024'
```