// ============================================================================
// App Service module - Linux .NET 8 web app running the catalog.
//   * VNet-integrated into snet-appsvc for private outbound to the Oracle VM.
//   * Inbound access restricted to the Application Gateway subnet only.
//   * Oracle connection string injected as a Custom connection string, which
//     ASP.NET Core surfaces as ConnectionStrings:Catalog.
//   * Health probe path set to /healthz.
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Globally-unique web app name.')
param webAppName string

@description('App Service plan SKU.')
param planSku string = 'P0v3'

@description('Subnet id for VNet integration (snet-appsvc, delegated).')
param appSvcSubnetId string

@description('Application Gateway subnet id allowed to reach the app (requires a Microsoft.Web service endpoint on that subnet).')
param appGwSubnetId string

@description('Private IP of the Oracle VM.')
param dbPrivateIp string

@description('Oracle service (PDB) name.')
param dbServiceName string

@description('Oracle application user.')
param dbUser string

@description('Oracle application password.')
@secure()
param dbPassword string

@description('Tags applied to all resources.')
param tags object = {}

var catalogConnectionString = 'User Id=${dbUser};Password=${dbPassword};Data Source=//${dbPrivateIp}:1521/${dbServiceName};'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${namePrefix}-plan'
  location: location
  tags: tags
  sku: {
    name: planSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  properties: {
    serverFarmId: plan.id
    virtualNetworkSubnetId: appSvcSubnetId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true
      http20Enabled: true
      vnetRouteAllEnabled: true
      healthCheckPath: '/healthz'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      connectionStrings: [
        {
          name: 'Catalog'
          type: 'Custom'
          connectionString: catalogConnectionString
        }
      ]
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
      ]
      ipSecurityRestrictions: [
        {
          name: 'Allow-AppGateway'
          action: 'Allow'
          priority: 100
          vnetSubnetResourceId: appGwSubnetId
        }
      ]
    }
  }
}

output webAppName string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
