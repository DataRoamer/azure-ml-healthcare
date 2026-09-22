using './identity.bicep'

// Confirm these two with:
//   az ml workspace list -o table
//   az ml workspace show -n <workspace> -g <rg> --query storage_account -o tsv
param workspaceName = 'automl_exp'
param storageAccountName = '<the storage account your workspace already uses>'

param githubOwner = '<your-github-username>'
param githubRepo = 'azure-ml-healthcare'

param identityName = 'id-ai300-github'

param githubEnvironment = 'production'
