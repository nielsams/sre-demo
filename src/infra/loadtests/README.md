# Load tests (Azure Load Testing)

Two JMeter test plans targeting the PC Depot catalog app through the
Application Gateway (`http://pcdepot-...cloudapp.azure.com`). They run on the
`pcdepot-loadtest` Azure Load Testing resource (provisioned by
`modules/loadtesting.bicep`).

| Test | Plan | Load | Purpose |
|------|------|------|---------|
| `pcdepot-normal-traffic` | `normal-traffic.jmx` | 1 engine x 25 VUs, think time, 5 min | Expected steady-state load; app stays healthy |
| `pcdepot-stress-traffic` | `stress-traffic.jmx` | 5 engines x 250 VUs (1250), no think time, 5 min, autoStop disabled | Overloads App Service + Oracle DB to cause failures |

The target host is passed to JMeter via the `domain` environment variable in
each `*.yaml` config (read in the plan with `${__BeanShell(System.getenv("domain"))}`),
so the plans are reusable against a different deployment by editing the YAML.

## (Re)create the tests

```bash
cd src/infra/loadtests
az load test create -t pcdepot-normal-traffic --load-test-resource pcdepot-loadtest -g sre-demo-01 --load-test-config-file normal-traffic.yaml
az load test create -t pcdepot-stress-traffic --load-test-resource pcdepot-loadtest -g sre-demo-01 --load-test-config-file stress-traffic.yaml
```

## Run a test

```bash
az load test-run create --load-test-resource pcdepot-loadtest -g sre-demo-01 \
  --test-id pcdepot-normal-traffic --test-run-id normal-$(date +%s)
```

Run the normal test first to capture a healthy baseline, then the stress test
to observe degradation (rising latency, 5xx, DB connection exhaustion) in the
`pcdepot-law` Log Analytics workspace.
