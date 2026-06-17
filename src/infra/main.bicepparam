using './main.bicep'

// Fill in secrets before deploying, or pass them on the command line / via the
// deploy script. Do NOT commit real passwords.

param namePrefix = 'pcdepot'
param vmAdminUsername = 'azureuser'
param vmAdminPassword = '' // set via deploy script or CLI override
param dbUser = 'CATALOG'
param dbPassword = '' // set via deploy script or CLI override
param dbServiceName = 'ORCLPDB1'
param vmSize = 'Standard_E4ds_v5'
