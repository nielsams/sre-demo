// ============================================================================
// Network module - VNet (10.11.0.0/16), subnets and NSGs.
// Subnet layout:
//   snet-appgw   10.11.0.0/24  Application Gateway
//   snet-appsvc  10.11.1.0/24  App Service VNet integration (delegated)
//   snet-db      10.11.2.0/24  Oracle VM (private, locked to App Service)
// ============================================================================

@description('Azure region for all resources.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Tags applied to all resources.')
param tags object = {}

var vnetAddressSpace = '10.11.0.0/16'
var appGwSubnetPrefix = '10.11.0.0/24'
var appSvcSubnetPrefix = '10.11.1.0/24'
var dbSubnetPrefix = '10.11.2.0/24'

resource appGwNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-appgw-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Internet-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [ '80', '443' ]
        }
      }
      {
        name: 'Allow-GatewayManager'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
    ]
  }
}

resource dbNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-db-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Oracle-From-AppSvc'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appSvcSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: dbSubnetPrefix
          destinationPortRange: '1521'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressSpace ]
    }
    subnets: [
      {
        name: 'snet-appgw'
        properties: {
          addressPrefix: appGwSubnetPrefix
          networkSecurityGroup: { id: appGwNsg.id }
          serviceEndpoints: [
            {
              service: 'Microsoft.Web'
            }
          ]
        }
      }
      {
        name: 'snet-appsvc'
        properties: {
          addressPrefix: appSvcSubnetPrefix
          delegations: [
            {
              name: 'webapp-delegation'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: 'snet-db'
        properties: {
          addressPrefix: dbSubnetPrefix
          networkSecurityGroup: { id: dbNsg.id }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output appGwSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-appgw')
output appSvcSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-appsvc')
output dbSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-db')
