// Azure Firewall Explicit Proxy test lab (preview feature)
// Standard tier firewall + explicit proxy + Linux client VM + Bastion

@description('Deployment region')
param location string = resourceGroup().location

@description('Admin username for the Linux client VM')
param adminUsername string = 'azureuser'

@description('Admin password for the Linux client VM')
@secure()
param adminPassword string

@description('Explicit proxy HTTP listener port')
param httpPort int = 8080

@description('Explicit proxy HTTPS listener port')
param httpsPort int = 8443

@description('Client VM size')
param vmSize string = 'Standard_B2s'

var prefix = 'fwlab'

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'vnet-${prefix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.0.0.0/16' ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.1.0/26'
        }
      }
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
    ]
  }
}

resource fwPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-afw-${prefix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-bastion-${prefix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource fwPolicy 'Microsoft.Network/firewallPolicies@2024-07-01' = {
  name: 'fwpol-${prefix}'
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    explicitProxy: {
      enableExplicitProxy: true
      httpPort: httpPort
      httpsPort: httpsPort
      enablePacFile: false
    }
  }
}

resource ruleGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-07-01' = {
  parent: fwPolicy
  name: 'rcg-app'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-web'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-test-fqdns'
            sourceAddresses: [ '10.0.2.0/24' ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'www.microsoft.com'
              'ifconfig.me'
              'api.ipify.org'
              'ipinfo.io'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-07-01' = {
  name: 'afw-${prefix}'
  location: location
  dependsOn: [
    ruleGroup
  ]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: fwPolicy.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureFirewallSubnet'
          }
          publicIPAddress: {
            id: fwPip.id
          }
        }
      }
    ]
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: 'bastion-${prefix}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: 'nic-client-${prefix}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/snet-workload'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-client-${prefix}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'vm-client'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
  }
}

output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPublicIp string = fwPip.properties.ipAddress
output vmName string = vm.name
output vmAdminUsername string = adminUsername
output httpProxyPort int = httpPort
output httpsProxyPort int = httpsPort
output testHttpCommand string = 'curl -sS -x http://${firewall.properties.ipConfigurations[0].properties.privateIPAddress}:${httpPort} http://ifconfig.me'
output testHttpsCommand string = 'curl -sS -x http://${firewall.properties.ipConfigurations[0].properties.privateIPAddress}:${httpsPort} https://www.microsoft.com -o /dev/null -w "%{http_code}\\n"'
