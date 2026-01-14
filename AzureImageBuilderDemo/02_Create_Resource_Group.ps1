# Create the resource group

$resourceGroupName = "ImageBuilder-rg"
$location = "EastUS"
Write-Host "Creating resource group: $resourceGroupName in location: $location"
New-AzResourceGroup -Name $resourceGroupName -Location $location