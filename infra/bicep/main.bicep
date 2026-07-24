// main.bicep — AKS platform (faithful to deck Section 4 IaC excerpt, completed to a
// deployable/validatable template). Validate with:  az bicep build -f main.bicep
// Deploy with:  az deployment group create -g $RG -f main.bicep -p adminGroupObjectId=$ADMIN_GROUP
targetScope = 'resourceGroup'

@description('Azure region for the cluster.')
param location string = resourceGroup().location

@description('Entra ID group object ID granted cluster-admin via Azure RBAC.')
param adminGroupObjectId string

@description('DNS prefix / name seed.')
param prefix string = 'aksplat'

@description('Kubernetes version. Pin to a currently-available GA version in your region.')
param kubernetesVersion string = '1.31.1'

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: 'aks-${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Base', tier: 'Standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: prefix
    oidcIssuerProfile: { enabled: true }
    securityProfile: { workloadIdentity: { enabled: true } }
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: [ adminGroupObjectId ]
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.244.0.0/16'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        count: 3
        vmSize: 'Standard_D4s_v5'
        availabilityZones: [ '1', '2', '3' ]
      }
      {
        name: 'userpool'
        mode: 'User'
        count: 1
        minCount: 1
        maxCount: 3
        enableAutoScaling: true
        vmSize: 'Standard_D4s_v5'
        availabilityZones: [ '1', '2', '3' ]
      }
    ]
  }
}

output clusterName string = aks.name
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
