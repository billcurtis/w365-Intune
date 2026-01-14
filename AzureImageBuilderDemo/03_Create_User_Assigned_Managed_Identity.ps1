# Create User-Assigned Managed Identity and configure permissions for Azure Image Builder

$resourceGroupName = "ImageBuilder-rg"
$location = "EastUS"

# Get subscription ID
$subscriptionID = (Get-AzContext).Subscription.Id

# Create identity with timestamp
$timestamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$identityName = "aibBuiUserId$timestamp"

Write-Host "Creating user-assigned managed identity: $identityName"
$identity = New-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name $identityName -Location $location

# Get the identity client ID
$imgBuilderCliId = $identity.ClientId
Write-Host "Identity Client ID: $imgBuilderCliId"

# Get the user identity resource ID
$imgBuilderId = $identity.Id
Write-Host "Identity Resource ID: $imgBuilderId"

# Download the preconfigured role definition example
Write-Host "Downloading role definition template..."
$roleDefinitionUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$roleDefinitionPath = "aibRoleImageCreation.json"
Invoke-WebRequest -Uri $roleDefinitionUrl -OutFile $roleDefinitionPath

# Create custom role definition name with timestamp
$imageRoleDefName = "Azure Image Builder Image Def$timestamp"
Write-Host "Role definition name: $imageRoleDefName"

# Update the role definition with actual values
Write-Host "Updating role definition template..."
$roleDefinitionContent = Get-Content -Path $roleDefinitionPath -Raw
$roleDefinitionContent = $roleDefinitionContent -replace '<subscriptionID>', $subscriptionID
$roleDefinitionContent = $roleDefinitionContent -replace '<rgName>', $resourceGroupName
$roleDefinitionContent = $roleDefinitionContent -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName
Set-Content -Path $roleDefinitionPath -Value $roleDefinitionContent

# Create role definition
Write-Host "Creating custom role definition..."
$roleDefinition = New-AzRoleDefinition -InputFile $roleDefinitionPath

# Grant the role to the user-assigned identity
Write-Host "Assigning role to managed identity..."
$scope = "/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName"
New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName $imageRoleDefName -Scope $scope

# Grant Contributor role at subscription level so Image Builder can create staging resources
Write-Host "Granting Contributor role at subscription level for staging resource group creation..."
$subscriptionScope = "/subscriptions/$subscriptionID"
New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName "Contributor" -Scope $subscriptionScope -ErrorAction SilentlyContinue

# Grant Storage Blob Data Contributor at subscription level for staging storage access
Write-Host "Granting Storage Blob Data Contributor role at subscription level..."
New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $subscriptionScope -ErrorAction SilentlyContinue

Write-Host "`nWaiting 60 seconds for role assignments to propagate..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Host "User-assigned managed identity setup completed successfully!" -ForegroundColor Green
