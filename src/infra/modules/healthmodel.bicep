// ============================================================================
// Azure Health Model (Microsoft.CloudHealth) for the PC Depot demo app.
//   Models every resource in the deployment as an entity, wires up the
//   dependency topology, and derives health from Azure Monitor metrics via the
//   model's system-assigned managed identity (granted Reader on the RG).
//
//   API version 2026-01-01-preview has no built-in Azure Resource Health
//   signal, so the critical entities (App Gateway, App Service, Oracle VM)
//   carry explicit metric signals; the remaining resources are modelled as
//   topology entities (linked to their Azure resource) and roll up via
//   WorstOf dependency aggregation.
//
//   Topology (parent depends on child):
//     application
//       +- appgateway -> publicip, appgatewaynsg, vnet
//       +- appservice -> appserviceplan, vnet
//       +- oraclevm   -> oraclenic -> databasensg, vnet
//       +- logworkspace (Suppressed) -> dce, syslogdcr, oraclelogdcr
//       +- loadtest    (Suppressed)
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix (must match the other modules).')
param namePrefix string

@description('Globally-unique App Service name.')
param webAppName string

@description('Tags applied to the health model.')
param tags object = {}

// Resource IDs of everything in the deployment (names are deterministic).
var appgwId = resourceId('Microsoft.Network/applicationGateways', '${namePrefix}-appgw')
var pipId = resourceId('Microsoft.Network/publicIPAddresses', '${namePrefix}-appgw-pip')
var vnetId = resourceId('Microsoft.Network/virtualNetworks', '${namePrefix}-vnet')
var appgwNsgId = resourceId('Microsoft.Network/networkSecurityGroups', '${namePrefix}-appgw-nsg')
var dbNsgId = resourceId('Microsoft.Network/networkSecurityGroups', '${namePrefix}-db-nsg')
var appServiceId = resourceId('Microsoft.Web/sites', webAppName)
var planId = resourceId('Microsoft.Web/serverfarms', '${namePrefix}-plan')
var vmId = resourceId('Microsoft.Compute/virtualMachines', '${namePrefix}-oracle-vm')
var nicId = resourceId('Microsoft.Network/networkInterfaces', '${namePrefix}-oracle-nic')
var lawId = resourceId('Microsoft.OperationalInsights/workspaces', '${namePrefix}-law')
var dceId = resourceId('Microsoft.Insights/dataCollectionEndpoints', '${namePrefix}-dce')
var dcrSyslogId = resourceId('Microsoft.Insights/dataCollectionRules', '${namePrefix}-dcr-syslog')
var dcrOracleId = resourceId('Microsoft.Insights/dataCollectionRules', '${namePrefix}-dcr-oracle')
var loadTestId = resourceId('Microsoft.LoadTestService/loadTests', '${namePrefix}-loadtest')

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-01-01-preview' = {
  name: '${namePrefix}-healthmodel'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Reader lets the model's identity read Azure Monitor metrics and resource
// health for every resource it monitors.
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, healthModel.id, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: healthModel.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource authSetting 'Microsoft.CloudHealth/healthmodels/authenticationsettings@2026-01-01-preview' = {
  parent: healthModel
  name: 'default'
  properties: {
    displayName: 'System-assigned managed identity'
    authenticationKind: 'ManagedIdentity'
    managedIdentityName: 'SystemAssigned'
  }
}

// ---------------------------------------------------------------------------
// Root application entity (pure aggregator).
// ---------------------------------------------------------------------------
resource appEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'application'
  properties: {
    displayName: 'PC Depot Catalog'
    impact: 'Standard'
    healthObjective: 99
    canvasPosition: { x: 640, y: 40 }
    signalGroups: {
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Critical entities: own metric signal + dependency roll-up.
// ---------------------------------------------------------------------------
resource appgwEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'appgateway'
  properties: {
    displayName: 'Application Gateway'
    impact: 'Standard'
    canvasPosition: { x: 640, y: 180 }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: appgwId
        signals: [
          {
            name: 'unhealthyHosts'
            displayName: 'Unhealthy backend hosts'
            signalKind: 'AzureResourceMetric'
            metricNamespace: 'Microsoft.Network/applicationGateways'
            metricName: 'UnhealthyHostCount'
            aggregationType: 'Maximum'
            dataUnit: 'Count'
            timeGrain: 'PT5M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              unhealthyRule: { operator: 'GreaterThanOrEqual', threshold: 1 }
            }
          }
        ]
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource appServiceEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'appservice'
  properties: {
    displayName: 'App Service (web app)'
    impact: 'Standard'
    canvasPosition: { x: 380, y: 320 }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: appServiceId
        signals: [
          {
            name: 'http5xx'
            displayName: 'HTTP 5xx responses'
            signalKind: 'AzureResourceMetric'
            metricNamespace: 'Microsoft.Web/sites'
            metricName: 'Http5xx'
            aggregationType: 'Total'
            dataUnit: 'Count'
            timeGrain: 'PT5M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              degradedRule: { operator: 'GreaterThan', threshold: 0 }
              unhealthyRule: { operator: 'GreaterThan', threshold: 10 }
            }
          }
        ]
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource vmEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'oraclevm'
  properties: {
    displayName: 'Oracle Database VM'
    impact: 'Standard'
    canvasPosition: { x: 860, y: 320 }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: vmId
        signals: [
          {
            name: 'vmAvailability'
            displayName: 'VM availability'
            signalKind: 'AzureResourceMetric'
            metricNamespace: 'Microsoft.Compute/virtualMachines'
            metricName: 'VmAvailabilityMetric'
            aggregationType: 'Average'
            dataUnit: 'Count'
            timeGrain: 'PT5M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              unhealthyRule: { operator: 'LessThan', threshold: 1 }
            }
          }
        ]
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Aggregator entities without their own metric (topology + roll-up).
// ---------------------------------------------------------------------------
resource nicEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'oraclenic'
  properties: {
    displayName: 'Oracle VM NIC'
    impact: 'Standard'
    canvasPosition: { x: 860, y: 460 }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: nicId
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource lawEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = {
  parent: healthModel
  name: 'logworkspace'
  properties: {
    displayName: 'Log Analytics Workspace'
    impact: 'Suppressed'
    canvasPosition: { x: 1140, y: 320 }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: lawId
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Leaf entities (topology, linked to their Azure resource).
// ---------------------------------------------------------------------------
var leafEntities = [
  { name: 'publicip', displayName: 'App Gateway Public IP', resId: pipId, impact: 'Standard', x: 480, y: 180 }
  { name: 'appgatewaynsg', displayName: 'App Gateway NSG', resId: appgwNsgId, impact: 'Limited', x: 800, y: 180 }
  { name: 'appserviceplan', displayName: 'App Service Plan', resId: planId, impact: 'Standard', x: 380, y: 460 }
  { name: 'databasensg', displayName: 'Database NSG', resId: dbNsgId, impact: 'Limited', x: 1020, y: 600 }
  { name: 'vnet', displayName: 'Virtual Network', resId: vnetId, impact: 'Standard', x: 640, y: 620 }
  { name: 'datacollectionendpoint', displayName: 'Data Collection Endpoint', resId: dceId, impact: 'Suppressed', x: 1080, y: 460 }
  { name: 'syslogdcr', displayName: 'Syslog DCR', resId: dcrSyslogId, impact: 'Suppressed', x: 1200, y: 460 }
  { name: 'oraclelogdcr', displayName: 'Oracle Log DCR', resId: dcrOracleId, impact: 'Suppressed', x: 1320, y: 460 }
  { name: 'loadtest', displayName: 'Load Testing', resId: loadTestId, impact: 'Suppressed', x: 200, y: 180 }
]

resource leafEntityResources 'Microsoft.CloudHealth/healthmodels/entities@2026-01-01-preview' = [for e in leafEntities: {
  parent: healthModel
  name: e.name
  properties: {
    displayName: e.displayName
    impact: e.impact
    canvasPosition: { x: e.x, y: e.y }
    signalGroups: {
      azureResource: {
        authenticationSetting: authSetting.name
        azureResourceId: e.resId
      }
    }
  }
}]

// ---------------------------------------------------------------------------
// Relationships (parent depends on child).
// ---------------------------------------------------------------------------
var relationships = [
  { name: 'app-to-appgateway', p: 'application', c: 'appgateway' }
  { name: 'app-to-appservice', p: 'application', c: 'appservice' }
  { name: 'app-to-oraclevm', p: 'application', c: 'oraclevm' }
  { name: 'app-to-logworkspace', p: 'application', c: 'logworkspace' }
  { name: 'app-to-loadtest', p: 'application', c: 'loadtest' }
  { name: 'appgateway-to-publicip', p: 'appgateway', c: 'publicip' }
  { name: 'appgateway-to-nsg', p: 'appgateway', c: 'appgatewaynsg' }
  { name: 'appgateway-to-vnet', p: 'appgateway', c: 'vnet' }
  { name: 'appservice-to-plan', p: 'appservice', c: 'appserviceplan' }
  { name: 'appservice-to-vnet', p: 'appservice', c: 'vnet' }
  { name: 'oraclevm-to-nic', p: 'oraclevm', c: 'oraclenic' }
  { name: 'oraclenic-to-nsg', p: 'oraclenic', c: 'databasensg' }
  { name: 'oraclenic-to-vnet', p: 'oraclenic', c: 'vnet' }
  { name: 'logworkspace-to-dce', p: 'logworkspace', c: 'datacollectionendpoint' }
  { name: 'logworkspace-to-syslogdcr', p: 'logworkspace', c: 'syslogdcr' }
  { name: 'logworkspace-to-oraclelogdcr', p: 'logworkspace', c: 'oraclelogdcr' }
]

resource relationshipResources 'Microsoft.CloudHealth/healthmodels/relationships@2026-01-01-preview' = [for r in relationships: {
  parent: healthModel
  name: r.name
  properties: {
    parentEntityName: r.p
    childEntityName: r.c
  }
  dependsOn: [
    appEntity
    appgwEntity
    appServiceEntity
    vmEntity
    nicEntity
    lawEntity
    leafEntityResources
  ]
}]

output healthModelName string = healthModel.name
output healthModelId string = healthModel.id
output healthModelPrincipalId string = healthModel.identity.principalId
