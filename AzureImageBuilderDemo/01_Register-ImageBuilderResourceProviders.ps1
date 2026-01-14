# Register necessary resource providers for Image Builder in the current subscription
$resourceProviders = @(
    "Microsoft.VirtualMachineImages",
    "Microsoft.Compute",
    "Microsoft.Storage",
    "Microsoft.Network",
    "Microsoft.KeyVault",
    "Microsoft.Containerservice"
)

foreach ($provider in $resourceProviders) {
    Write-Host "Registering resource provider: $provider"
    Register-AzResourceProvider -ProviderNamespace $provider
}   

