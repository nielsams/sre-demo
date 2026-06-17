// ============================================================================
// Monitoring module - Log Analytics workspace + diagnostic settings.
//   Creates a workspace and points every resource that supports resource-level
//   diagnostic settings (App Gateway, App Service, public IP, VNet, NSGs) at it,
//   sending all log categories (allLogs) and, where supported, all metrics.
//
//   NOTE: The Oracle VM is intentionally not included -- virtual machines do not
//   expose resource-level diagnostic settings; guest OS/Oracle logs require the
//   Azure Monitor Agent + a Data Collection Rule, which is out of scope here.
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix (must match the other modules).')
param namePrefix string

@description('Globally-unique App Service name.')
param webAppName string

@description('Retention in days for the Log Analytics workspace.')
param retentionInDays int = 30

@description('Tags applied to the workspace.')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ---- Existing resources to attach diagnostics to ---------------------------
resource appGw 'Microsoft.Network/applicationGateways@2023-11-01' existing = {
  name: '${namePrefix}-appgw'
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: '${namePrefix}-appgw-pip'
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: '${namePrefix}-vnet'
}

resource appGwNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: '${namePrefix}-appgw-nsg'
}

resource dbNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: '${namePrefix}-db-nsg'
}

resource webApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: webAppName
}

var diagName = 'to-law'

// ---- Diagnostic settings (logs + metrics) ----------------------------------
resource appGwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: appGw
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource webAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: webApp
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource publicIpDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: publicIp
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource vnetDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: vnet
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// NSGs support log categories only (no metrics in diagnostic settings).
resource appGwNsgDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: appGwNsg
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

resource dbNsgDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagName
  scope: dbNsg
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output workspaceId string = law.id
output workspaceName string = law.name
