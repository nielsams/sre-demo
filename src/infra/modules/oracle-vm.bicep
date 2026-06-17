// ============================================================================
// Oracle VM module - Oracle Database 21c on a Linux VM from the Azure
// Marketplace (Oracle:oracle-database:oracle_db_21). Private NIC only (no
// public IP); reachable only from the App Service subnet over port 1521
// (enforced by the db NSG).
//
// NOTE: This image has no marketplace 'plan' (plan == null), so the VM does
// NOT declare a plan block and no `az vm image terms accept` step is required.
// ============================================================================

@description('Azure region.')
param location string

@description('Resource name prefix.')
param namePrefix string

@description('Subnet resource id for the database NIC.')
param dbSubnetId string

@description('Static private IP for the Oracle VM (inside the db subnet).')
param privateIp string = '10.11.2.10'

@description('VM size.')
param vmSize string = 'Standard_E4ds_v5'

@description('Admin username for the VM.')
param adminUsername string

@description('Admin password for the VM (also used to bootstrap the database).')
@secure()
param adminPassword string

@description('Marketplace image reference for Oracle Database 21c.')
param imagePublisher string = 'Oracle'
param imageOffer string = 'oracle-database'
param imageSku string = 'oracle_db_21'
param imageVersion string = 'latest'

@description('OS disk size in GB.')
param osDiskSizeGb int = 128

@description('Tags applied to all resources.')
param tags object = {}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${namePrefix}-oracle-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
          subnet: { id: dbSubnetId }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${namePrefix}-oracle-vm'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'oracledb'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
}

output vmName string = vm.name
output privateIp string = privateIp
