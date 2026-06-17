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

resource oracleVm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: '${namePrefix}-oracle-vm'
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

// ============================================================================
// Oracle VM: Azure Monitor Agent + Data Collection Rule (Linux syslog).
//   VMs have no resource-level diagnostic settings, so guest logs are collected
//   by AMA and routed to the workspace via a DCR + association. AMA authenticates
//   using the VM's system-assigned managed identity.
// ============================================================================

resource syslogDcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${namePrefix}-dcr-syslog'
  location: location
  tags: tags
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'syslogBase'
          streams: [ 'Microsoft-Syslog' ]
          facilityNames: [ '*' ]
          logLevels: [ '*' ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'laDest'
          workspaceResourceId: law.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-Syslog' ]
        destinations: [ 'laDest' ]
      }
    ]
  }
}

resource amaLinux 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: oracleVm
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Link the VM to the DCR (scoped to the VM as an extension resource).
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${namePrefix}-dcr-assoc'
  scope: oracleVm
  properties: {
    dataCollectionRuleId: syslogDcr.id
  }
  dependsOn: [
    amaLinux
  ]
}

output dataCollectionRuleId string = syslogDcr.id

// ============================================================================
// Oracle application logs (alert log + listener log) via AMA custom text logs.
//   A DCR-based custom table receives each log line as RawData; a second DCR
//   with a logFiles data source tails the Oracle diag files and ships them to
//   the workspace. AMA reads the files directly (no rsyslog involved).
// ============================================================================

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: '${namePrefix}-dce'
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource oracleLogTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {  parent: law
  name: 'OracleLogs_CL'
  properties: {
    retentionInDays: retentionInDays
    schema: {
      name: 'OracleLogs_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'RawData', type: 'string' }
        { name: 'FilePath', type: 'string' }
        { name: 'Computer', type: 'string' }
      ]
    }
  }
}

resource oracleDcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${namePrefix}-dcr-oracle'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-OracleLogs_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'RawData', type: 'string' }
          { name: 'FilePath', type: 'string' }
          { name: 'Computer', type: 'string' }
        ]
      }
    }
    dataSources: {
      logFiles: [
        {
          name: 'oracleTextLogs'
          streams: [ 'Custom-OracleLogs_CL' ]
          filePatterns: [
            '/u01/app/oracle/diag/rdbms/orcl/ORCL/trace/alert_*.log'
            '/u01/app/oracle/diag/tnslsnr/oracledb/listener/trace/listener.log'
          ]
          format: 'text'
          settings: {
            text: {
              recordStartTimestampFormat: 'ISO 8601'
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'laDest'
          workspaceResourceId: law.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-OracleLogs_CL' ]
        destinations: [ 'laDest' ]
        transformKql: 'source'
        outputStream: 'Custom-OracleLogs_CL'
      }
    ]
  }
  dependsOn: [
    oracleLogTable
  ]
}

resource oracleDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${namePrefix}-dcr-oracle-assoc'
  scope: oracleVm
  properties: {
    dataCollectionRuleId: oracleDcr.id
  }
  dependsOn: [
    amaLinux
  ]
}

output oracleDataCollectionRuleId string = oracleDcr.id
