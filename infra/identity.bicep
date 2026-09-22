// =============================================================================
// AI-300 Step 1.4 — the CI identity, as code.
//
// This template deploys into your EXISTING resource group and creates nothing
// billable: one user-assigned managed identity, one federated credential, and
// two role assignments. It does NOT create a workspace, storage account,
// key vault or registry — it references the ones you already have.
//
// Preview:  az deployment group what-if -g <rg> -f infra/identity.bicep -p infra/identity.bicepparam
// Deploy:   az deployment group create  -g <rg> -f infra/identity.bicep -p infra/identity.bicepparam
// =============================================================================

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

// Built-in role definition IDs. Verified against the built-in role list.
var azureMLDataScientist = 'f6c7c914-8db3-469d-8ca1-694a8f32e121'
var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// --- Existing resources: referenced, never created or modified --------------

resource workspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' existing = {
  name: workspaceName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// --- The identity GitHub will become ----------------------------------------

resource ciIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// --- The trust relationship that replaces the client secret -----------------
// subject is an EXACT match. This one covers pushes to main and nothing else.
// A tag, a pull request or another branch each need their own credential.

resource federationMain 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: ciIdentity
  name: 'github-main'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepo}:ref:refs/heads/main'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
}

// The second context. Note what is NOT happening here: this is not an extra
// permission, and it does not widen anything. Both credentials lead to the same
// identity holding the same two roles. All that differs is which workflow
// context Entra ID will accept a token from.
//
// The gotcha worth experiencing: the moment a job declares
// `environment: production`, its token's subject becomes the environment form
// and STOPS being the ref form — even on a push to main. So a job with an
// environment will fail against the credential above until this one exists.
resource federationEnvironment 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: ciIdentity
  name: 'github-env-${githubEnvironment}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/${githubRepo}:environment:${githubEnvironment}'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
  // Federated credentials on one identity must be created one at a time.
  dependsOn: [ federationMain ]
}

// --- Least privilege --------------------------------------------------------

// Scoped to the workspace, not the resource group or subscription.
// Data Scientist can submit and manage jobs. Its NotActions exclude creating
// or deleting compute and modifying the workspace, so CI cannot delete the
// workspace it runs against. Submitting a job to an existing cluster triggers
// autoscale on its own, so no compute role is needed.
resource dataScientistOnWorkspace 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, ciIdentity.id, azureMLDataScientist)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureMLDataScientist)
    principalId: ciIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// The data-plane half from Step 1.2. Job submission uploads a code snapshot to
// the workspace default datastore, which is blob content — the workspace role
// above does not cover it.
resource blobWriterOnStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, ciIdentity.id, storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributor)
    principalId: ciIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Outputs: identifiers, not credentials ----------------------------------

output clientId string = ciIdentity.properties.clientId
output principalId string = ciIdentity.properties.principalId
output tenantId string = subscription().tenantId
output subscriptionId string = subscription().subscriptionId

