# Performance Tests

This folder has scripts and resources that can execute performance tests to examine the performance of Ambient and compare it to Istio or no-mesh setups.

The test deploys a client and a server deployments with anti-affinity that guarantees they are deployed on different nodes.
The script will execute a [nighthawk](https://github.com/envoyproxy/nighthawk) client that will send requests to the server service which is also a nighthawk running in a server mode.

## Dependencies

* The performance test script in this project are executing redirection scripts and Istio installation from the [Istio Sidecarless](https://github.com/solo-io/istio-sidecarless) repo.
By default it assumes the repo has been cloned under the same parent directory of this repo. If it's in a different path, modify the `AMBIENT_REPO_DIR` variable in the script below.

* The PEPs are using the images from `$HUB` and `$TAG`. Make sure they are set and reference a valid pushed image.

## Running

The [run_perf_tests.sh](run_perf_tests.sh) script will use the K8s cluster in the current config context for running the performance tests in different configurations:
* No mesh (pure K8s)
* Istio Sidecars
* Linkerd Proxy (only tested if LINKERD environment variable is defined, simplest way is `LINKERD=1`)
* Ambient (only uProxies)
* Ambient (uProxies and PEPs)

The script assumes the cluster has no workloads or configuration from past execution (i.e. No Istio, performance test workloads and Ambient redirection has been cleaned).

To execute the script run it from the project root folder:
```sh
./run_perf_tests.sh
```

Output to the execution will be written to the output file mentioned in the script in a CSV format. Example:

```csv
Run time: Mon Jul 11 10:35:26 IDT 2022
Nighthawk client parameters: --concurrency 1 --output-format json --rps 200 --duration 10
Service port name: tcp-enforcment

,No Mesh,With Istio Sidecars,Ambient (only uProxies),Ambient (uProxies + PEPs),
p50,0.999807,1.20141,1.35635,1.63411,
p90,1.20627,1.52237,2.02035,2.86694,
p99,5.14918,5.61587,6.44147,21.0422,
Max,31.6416,18.8078,16.1807,77.7257,
```

You can convert the CSV portion of the results to a nice table with conv_results.sh:

```sh
./conv_results.txt
```

This will output the results in an ASCII table to stdout.

## Few Things To Notice
* mTLS is enabled in the service mesh in the Istio/Ambient scenarios
* You can modify the scripts arguments to change the tests behavior. See script variables descriptions below.
* The reason for manually deploying the PEPs resources instead of Gateways is to make sure the client PEP is on the same node of the client workload and the similar requirement for the server PEP.

## Variables in the script

* `NIGHTHAWK_PARAMS` - These are the arguments passed to the nighthawk when running it as a client. By default the arguments conducts a 400 requests per second with no concurrency for 60s and output the results to Json file. By default nighthawk would open 100 connections during this test. See the [Nighhawk client CLI documentation](https://github.com/envoyproxy/nighthawk#using-the-nighthawk-client-cli) for the full list of supported parameters.

* `RESULTS_FILE` - Name of the file that will hold the overall all results such as the above.

* `SERVICE_PORT_NAME` - The port name to be used in the `Service` resources for the server. By default it explicity enforces tcp to avoid the protocol sniffing / HTTP handling. Change this to a name prefixed by `http-` to treat the traffic as HTTP.

* `AMBIENT_REPO_DIR` - The directory where `istio-sidecarless` project exist. By default it is assumed to be in the parent folder of this project.
