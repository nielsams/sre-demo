// ============================================================================
// Azure Load Testing resource. The resource is a managed test-runner host; the
// actual test definitions (JMeter plans + load config) live under
// src/infra/loadtests/ and are uploaded with `az load test create`.
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Tags applied to all resources.')
param tags object = {}

resource loadTest 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: '${namePrefix}-loadtest'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Load testing for the PC Depot demo catalog app (via Application Gateway).'
  }
}

output loadTestName string = loadTest.name
output loadTestId string = loadTest.id
