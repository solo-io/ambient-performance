# iperf3

Houses the iperf3 dockerfile used for performance testing of ambient.

## Building and pushing

Typical usage:

```bash
docker build -t us-west3-docker.pkg.dev/solo-test-236622/daniel-solo/iperf3:latest .
docker push us-west3-docker.pkg.dev/solo-test-236622/daniel-solo/iperf3:latest
```