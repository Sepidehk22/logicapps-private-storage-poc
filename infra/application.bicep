targetScope = 'resourceGroup'

@description('Same environment identifier as foundation.bicep, in the same resource group.')
@minLength(1)
param environmentName string

@description('Same approved region as the existing ASE.')
@minLength(1)
param location string

@description('Actual DNS suffix read from the Ready internal ASE. Do not invent this value.')
@minLength(1)
param aseDnsSuffix string

@description('Actual internal ASE VIP, read after foundation deployment.')
@minLength(1)
param aseInternalIp string

@description('Same existing resolver VNet IDs as the foundation stage.')
@minLength(1)
param resolverVnetResourceIds array

param tags object = {}

var suffix = uniqueString(resourceGroup().id, environmentName)
resource ase 'Microsoft.Web/hostingEnvironments@2024-11-01' existing = { name: 'ase-${suffix}' }
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: 'vnet-${suffix}' }
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = { name: 'st${suffix}' }
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-${suffix}' }
resource insights 'Microsoft.Insights/components@2020-02-02' existing = { name: 'ai-${suffix}' }
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = { name: 'log-${suffix}' }

resource aseZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: aseDnsSuffix
  location: 'global'
  tags: tags
}
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: aseZone
  name: 'ase-vnet'
  location: 'global'
  properties: { virtualNetwork: { id: vnet.id }, registrationEnabled: false }
}
resource resolverLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for vnetId in resolverVnetResourceIds: {
  parent: aseZone
  name: 'resolver-${uniqueString(vnetId)}'
  location: 'global'
  properties: { virtualNetwork: { id: vnetId }, registrationEnabled: false }
}]
resource aseRecords 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [for record in ['@', '*', '*.scm']: {
  parent: aseZone
  name: record
  properties: { ttl: 60, aRecords: [{ ipv4Address: aseInternalIp }] }
}]

resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: 'asp-${suffix}'
  location: location
  tags: tags
  sku: { name: 'I1v2', tier: 'IsolatedV2', capacity: 1 }
  properties: { reserved: false, hostingEnvironmentProfile: { id: ase.id } }
}
resource app 'Microsoft.Web/sites@2024-11-01' = {
  name: 'la-${suffix}'
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
  properties: {
    serverFarmId: plan.id
    hostingEnvironmentProfile: { id: ase.id }
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      use32BitWorkerProcess: false
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      cors: { allowedOrigins: ['https://portal.azure.com'], supportCredentials: false }
      appSettings: [
        { name: 'APP_KIND', value: 'workflowApp' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'dotnet' }
        { name: 'AzureWebJobsStorage__managedIdentityResourceId', value: identity.id }
        { name: 'AzureWebJobsStorage__credential', value: 'managedIdentity' }
        { name: 'AzureWebJobsStorage__blobServiceUri', value: 'https://${storage.name}.blob.${environment().suffixes.storage}' }
        { name: 'AzureWebJobsStorage__queueServiceUri', value: 'https://${storage.name}.queue.${environment().suffixes.storage}' }
        { name: 'AzureWebJobsStorage__tableServiceUri', value: 'https://${storage.name}.table.${environment().suffixes.storage}' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING', value: 'Authorization=AAD;ClientId=${identity.properties.clientId}' }
      ]
    }
  }
  dependsOn: [vnetLink, resolverLinks, aseRecords]
}
resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  parent: app
  name: 'scm'
  properties: { allow: false }
}
resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-11-01' = {
  parent: app
  name: 'ftp'
  properties: { allow: false }
}
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'workflow-runtime'
  scope: app
  properties: {
    workspaceId: workspace.id
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output appName string = app.name
output planName string = plan.name
output privateAppUrl string = 'https://${app.properties.defaultHostName}'
