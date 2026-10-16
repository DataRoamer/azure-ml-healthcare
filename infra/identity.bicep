// Managed identity used by GitHub Actions to submit Azure ML jobs,
// with only the permissions it needs.
// Deploys into an existing resource group and creates no billable resources:
// one managed identity, two federated credentials and two role assignments.
// The workspace and its storage account must already exist.
//
// Preview:  az deployment group what-if -g <rg> -f infra/identity.bicep -p infra/identity.bicepparam
// Deploy:   az deployment group create  -g <rg> -f infra/identity.bicep -p infra/identity.bicepparam

targetScope = 'resourceGroup'

@description('Name of your EXISTING Azure ML workspace. Find it with: az ml workspace list -o table')
param workspaceName string

@description('Name of the storage account the workspace already uses. Find it with: az ml workspace show -n <ws> -g <rg> --query storage_account -o tsv')
param storageAccountName string

@description('GitHub org or username that owns the repo.')
param githubOwner string

@description('GitHub repository name.')
param githubRepo string

@description('GitHub environment to federate as well, e.g. production. Put required reviewers on it in GitHub and you have an approval gate no client secret could ever give you.')
param githubEnvironment string = 'production'

@description('Name for the CI identity.')
param identityName string = 'id-ai300-github'

param location string = resourceGroup().location

// Azure built-in role IDs.
var azureMLDataScientist = 'f6c7c914-8db3-469d-8ca1-694a8f32e121'
var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Existing workspace and storage. This file does not create or change them.

resource workspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' existing = {
  name: workspaceName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Identity that GitHub Actions signs in as.

resource ciIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// Trust GitHub login tokens, but only for pushes to the main branch of this repo.
// The subject must match exactly, so other branches, tags and pull requests are not trusted.

resource federationMain 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: ciIdentity
  name: 'github-main'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepo}:ref:refs/heads/main'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
}

// Second trust rule, for jobs that run in the GitHub 'production' environment,
// which can require someone to approve a run. It adds no extra permissions.
// A job that uses an environment sends a different token subject, so it needs this rule.
resource federationEnvironment 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: ciIdentity
  name: 'github-env-${githubEnvironment}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepo}:environment:${githubEnvironment}'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
  // Federated credentials on one identity must be added one at a time.
  dependsOn: [ federationMain ]
}

// Lets the identity submit jobs to this workspace only.
// It cannot delete the workspace or create compute.
resource dataScientistOnWorkspace 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, ciIdentity.id, azureMLDataScientist)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureMLDataScientist)
    principalId: ciIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Lets the identity upload the code snapshot to the workspace storage,
// which every job submission needs.
resource blobWriterOnStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, ciIdentity.id, storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributor)
    principalId: ciIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Values to copy into GitHub. These are identifiers, not passwords.

output clientId string = ciIdentity.properties.clientId
output principalId string = ciIdentity.properties.principalId
output tenantId string = subscription().tenantId
output subscriptionId string = subscription().subscriptionId

