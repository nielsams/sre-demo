// ============================================================================
// Application Gateway module - public entry point for the catalog.
//   Internet -> Public IP -> App Gateway (v2) -> App Service backend (HTTPS).
//   Health probe hits /healthz on the backend.
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Subnet id for the Application Gateway (snet-appgw).')
param appGwSubnetId string

@description('Backend FQDN (App Service default host name).')
param backendFqdn string

@description('Availability zones for the public IP and gateway. Must match to avoid a zone mismatch (which surfaces as an AllowBringYourOwnPublicIpAddress error). Use [] for regions without zone support.')
param availabilityZones array = [ '1', '2', '3' ]

@description('Tags applied to all resources.')
param tags object = {}

var appGwName = '${namePrefix}-appgw'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${namePrefix}-appgw-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: availabilityZones
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${namePrefix}-${uniqueString(resourceGroup().id)}')
    }
  }
}

resource appGw 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGwName
  location: location
  tags: tags
  zones: availabilityZones
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: { id: appGwSubnetId }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFront'
        properties: {
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port80'
        properties: { port: 80 }
      }
    ]
    backendAddressPools: [
      {
        name: 'appservice-pool'
        properties: {
          backendAddresses: [
            { fqdn: backendFqdn }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          protocol: 'Https'
          path: '/healthz'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          match: {
            statusCodes: [ '200-399' ]
          }
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'https-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, 'health-probe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFront')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'route-to-appservice'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'http-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'appservice-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'https-settings')
          }
        }
      }
    ]
  }
}

output publicIpAddress string = publicIp.properties.ipAddress
output publicFqdn string = publicIp.properties.dnsSettings.fqdn
