targetScope = 'resourceGroup'

@description('Stable environment identifier. Use the same value in both stages.')
@minLength(1)
param environmentName string

@description('Approved region supporting internal ASE v3 and Windows I1v2.')
@minLength(1)
param location string

@description('Address space of the NEW dedicated VNet, without overlaps.')
param vnetAddressPrefix string

@description('Dedicated empty ASE subnet, normally /24.')
param aseSubnetPrefix string

@description('Private Endpoint subnet, separate from the ASE subnet.')
param privateEndpointSubnetPrefix string

@description('Reachable private customer DNS server IPs. Routing and forwarding are customer prerequisites.')
@minLength(1)
param dnsServerIps array

@description('Existing Azure VNet resource IDs hosting the customer DNS forwarders or inbound resolver. Adds DNS links only.')
@minLength(1)
param resolverVnetResourceIds array

@description('Keep false for network preparation. Set true only after customer routing and DNS checks pass.')
param deployAse bool

@description('Azure resource tags. Do not include confidential values.')
param tags object = {}

var suffix = uniqueString(resourceGroup().id, environmentName)
var storageServices = ['blob', 'queue', 'table']
var privateZoneNames = [
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.queue.${environment().suffixes.storage}'
  'privatelink.table.${environment().suffixes.storage}'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

resource aseNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-ase-${suffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowPlatformHealth'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowPrivateHttps'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${suffix}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [vnetAddressPrefix] }
    dhcpOptions: { dnsServers: dnsServerIps }
    subnets: [
      {
        name: 'ase'
        properties: {
          addressPrefix: aseSubnetPrefix
          networkSecurityGroup: { id: aseNsg.id }
          delegations: [
            { name: 'aseDelegation', properties: { serviceName: 'Microsoft.Web/hostingEnvironments' } }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for name in privateZoneNames: {
  name: name
  location: 'global'
  tags: tags
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in privateZoneNames: {
  parent: zones[i]
  name: 'ase-vnet'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }, registrationEnabled: false }
}]

// Flatten zone/VNet pairs so all zones are visible from the selected resolver VNets.
var resolverLinks = flatten(map(privateZoneNames, zoneName => map(resolverVnetResourceIds, vnetId => {
  zoneName: zoneName
  vnetId: vnetId
})))
resource resolverZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for link in resolverLinks: {
  name: '${link.zoneName}/resolver-${uniqueString(link.vnetId)}'
  location: 'global'
  properties: { virtualNetwork: { id: link.vnetId }, registrationEnabled: false }
  dependsOn: [zones]
}]

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${suffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}

resource storageEndpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for service in storageServices: {
  name: 'pe-${service}-${suffix}'
  location: location
  tags: tags
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [
      { name: service, properties: { privateLinkServiceId: storage.id, groupIds: [service] } }
    ]
  }
}]

resource storageZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [for (service, i) in storageServices: {
  parent: storageEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{ name: service, properties: { privateDnsZoneId: zones[i].id } }]
  }
}]

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${suffix}'
  location: location
  tags: tags
}

var storageRoleIds = [
  '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
]
resource storageRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in storageRoleIds: {
  name: guid(storage.id, identity.id, role)
  scope: storage
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
  }
}]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    DisableLocalAuth: true
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource monitoringRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(insights.id, identity.id, 'metricsPublisher')
  scope: insights
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

resource ampls 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: 'ampls-${suffix}'
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: { ingestionAccessMode: 'PrivateOnly', queryAccessMode: 'PrivateOnly' }
  }
}
resource insightsScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'insights'
  properties: { linkedResourceId: insights.id }
}
resource workspaceScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'workspace'
  properties: { linkedResourceId: workspace.id }
}
resource monitorEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-monitor-${suffix}'
  location: location
  tags: tags
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [
      { name: 'monitor', properties: { privateLinkServiceId: ampls.id, groupIds: ['azuremonitor'] } }
    ]
  }
  dependsOn: [insightsScope, workspaceScope]
}
resource monitorZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: monitorEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for i in [0, 3, 4, 5, 6]: {
      name: 'zone${i}'
      properties: { privateDnsZoneId: zones[i].id }
    }]
  }
}

resource ase 'Microsoft.Web/hostingEnvironments@2024-11-01' = if (deployAse) {
  name: 'ase-${suffix}'
  location: location
  tags: tags
  kind: 'ASEV3'
  properties: {
    internalLoadBalancingMode: 'Web, Publishing'
    zoneRedundant: false
    virtualNetwork: { id: '${vnet.id}/subnets/ase' }
  }
  dependsOn: [vnetLinks, resolverZoneLinks, storageZoneGroups, monitorZoneGroup]
}

output resourceNames object = {
  ase: 'ase-${suffix}'
  vnet: vnet.name
  storage: storage.name
  identity: identity.name
  insights: insights.name
  workspace: workspace.name
}
output vnetResourceId string = vnet.id
