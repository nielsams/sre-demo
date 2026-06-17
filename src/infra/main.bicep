// ============================================================================
// PC Parts Depot - end-to-end deployment for the Azure SRE agent demo.
//
//   Internet -> Public IP -> Application Gateway -> App Service (.NET 8)
//                                                       |
//                                                       v (VNet, private)
//                                              Oracle Database 21c VM
//
// Deploy into an EMPTY resource group:
//   az deployment group create -g <rg> -f main.bicep -p main.bicepparam
// Prefer the deploy.ps1 / deploy.sh wrappers, which also accept image terms
// and load the schema + seed data after provisioning.
// ============================================================================

targetScope = 'resourceGroup'

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Short prefix used to name all resources.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'pcdepot'

@description('Globally-unique App Service name.')
param webAppName string = '${namePrefix}-${uniqueString(resourceGroup().id)}'

@description('Admin username for the Oracle VM.')
param vmAdminUsername string

@description('Admin password for the Oracle VM.')
@secure()
param vmAdminPassword string

@description('Oracle application schema user the app connects as.')
param dbUser string = 'CATALOG'

@description('Password for the Oracle application user.')
@secure()
param dbPassword string

@description('Oracle service / pluggable database name.')
param dbServiceName string = 'ORCLPDB1'

@description('Oracle VM size.')
param vmSize string = 'Standard_E4ds_v5'

@description('Availability zones for the Application Gateway and its public IP. Both must match. Set to [] for regions that do not support availability zones.')
param appGatewayZones array = [ '1', '2', '3' ]

var tags = {
  workload: 'pcparts-depot'
  purpose: 'azure-sre-agent-demo'
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

module oracle 'modules/oracle-vm.bicep' = {
  name: 'oracle-vm'
  params: {
    location: location
    namePrefix: namePrefix
    dbSubnetId: network.outputs.dbSubnetId
    vmSize: vmSize
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    tags: tags
  }
}

module appService 'modules/appservice.bicep' = {
  name: 'appservice'
  params: {
    location: location
    namePrefix: namePrefix
    webAppName: webAppName
    appSvcSubnetId: network.outputs.appSvcSubnetId
    appGwSubnetId: network.outputs.appGwSubnetId
    dbPrivateIp: oracle.outputs.privateIp
    dbServiceName: dbServiceName
    dbUser: dbUser
    dbPassword: dbPassword
    tags: tags
  }
}

module appGateway 'modules/appgateway.bicep' = {
  name: 'appgateway'
  params: {
    location: location
    namePrefix: namePrefix
    appGwSubnetId: network.outputs.appGwSubnetId
    backendFqdn: appService.outputs.defaultHostName
    availabilityZones: appGatewayZones
    tags: tags
  }
}

@description('Public URL of the catalog (via Application Gateway).')
output siteUrl string = 'http://${appGateway.outputs.publicFqdn}'
output publicIpAddress string = appGateway.outputs.publicIpAddress
output webAppName string = appService.outputs.webAppName
output webAppHostName string = appService.outputs.defaultHostName
output oracleVmName string = oracle.outputs.vmName
output oraclePrivateIp string = oracle.outputs.privateIp
