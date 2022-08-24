# Performance Tests

This folder has scripts and resources that can execute performance tests to examine the performance of Ambient and compare it to Istio or no-mesh setups.

The test deploys a client and a server deployments with anti-affinity that guarantees they are deployed on different nodes.

For HTTP tests, the script will execute a [nighthawk](https://github.com/envoyproxy/nighthawk) client that will send requests to the server service which is also a nighthawk running in a server mode.

For TCP tests, the script will execute an [iperf3](https://iperf.fr) client that will send requests to an iperf3 server for a given number
of connections, defaulting to 1000.

## Dependencies

* yq and jq are required

* The performance test script in this project are executing redirection scripts and Istio installation from the [Istio Sidecarless](https://github.com/solo-io/istio-sidecarless) repo

By default it assumes the repo has been cloned under the same parent directory of this repo. If it's in a different path, set the `AMBIENT_REPO_DIR` environment variable using:

```bash
export AMBIENT_REPO_DIR=<path to repo>
```

This is solely to ensure we have access to the Ambient manifests and istioctl.

* The PEPs are using the images from `$HUB` and `$TAG`. Make sure they are set and reference a valid pushed image.

## Running with a config

To allow chaining multiple clusters with the same config, a number of changes have been made.

You can now use config.yaml to configure your test parameters.

Valid test types:
- http
- tcp
- tcp-throughput

Valid k8s types:
- kind (applies profile: ambient)
- aws (applies profile: ambient-aws)
- gcp (applies profile: ambient-gke)

An example:

```yaml
service_port_name: "http"
params: "--concurrency 1 --output-format json --rps 200 --duration 60"
final_result: "/tmp/results.txt"
hub: "harbor.hawton.haus/daniel"
tag: "ambient"
test_type: "tcp-throughput"
count: 4000 # Only applies to TCP tests, how many times to run the test
clusters:
- context: "kind-ambient"
  k8s_type: "kind"
  result_file: "/tmp/results-ambient-kind.csv"
- context: "daniel_hawton@daniel-ambient-perf.us-west-2.eksctl.io"
  k8s_type: "aws"
  result_file: "/tmp/results-ambient-aws.csv"
- context: "gke_solo-test-236622_us-west1-c_daniel-istio"
  k8s_type: "gcp"
  result_file: "/tmp/results-ambient-gke.csv"
```

Then just run:

```sh
./run_tests.sh
```

## Few Things To Notice
* mTLS is enabled in the service mesh in the Istio/Ambient scenarios
* You can modify the scripts arguments to change the tests behavior. See script variables descriptions below.
* The reason for manually deploying the PEPs resources instead of Gateways is to make sure the client PEP is on the same node of the client workload and the similar requirement for the server PEP.
