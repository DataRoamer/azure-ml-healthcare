using './identity.bicep'

// Confirm these two with:
//   az ml workspace list -o table
//   az ml workspace show -n <workspace> -g <rg> --query storage_account -o tsv
param workspaceName = 'automl_exp'
param storageAccountName = 'automlexp5779979870'

param githubOwner = 'DataRoamer'
param githubRepo = 'azure-ml-healthcare'

param identityName = 'id-ai300-github'

param githubEnvironment = 'production'
