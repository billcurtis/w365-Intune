# Create the Azure Image Builder template

$resourceGroupName = "ImageBuilder-rg"
$templateName = "Win11ImageTemplate"
$templateFile = "Win11ImageTemplate.json"

# Get subscription ID
$subscriptionID = (Get-AzContext).Subscription.Id

Write-Host "Reading template file: $templateFile"
$template = Get-Content -Path $templateFile -Raw | ConvertFrom-Json

Write-Host "Creating Image Builder template: $templateName"

# Use REST API to create the resource - extract only the resource body (identity, properties, location)
$apiVersion = "2024-02-01"
$uri = "/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.VirtualMachineImages/imageTemplates/$templateName`?api-version=$apiVersion"

# Build the resource body without ARM template metadata fields
$resourceBody = @{
    location = $template.location
    identity = $template.identity
    properties = $template.properties
}

$payload = $resourceBody | ConvertTo-Json -Depth 100

$response = Invoke-AzRestMethod -Method PUT -Path $uri -Payload $payload

if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
    Write-Host "Image Builder template created successfully!"
} else {
    Write-Host "Failed to create Image Builder template. Status Code: $($response.StatusCode)"
    Write-Host "Response: $($response.Content)"
}

Write-Host "Image Builder template created successfully!"
