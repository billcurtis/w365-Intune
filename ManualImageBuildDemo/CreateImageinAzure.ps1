# Upload VHD to Azure and Create Managed Image
# This script uploads a local VHD file to Azure Storage and creates a managed image from it

# Parameters
$vhdPath = "V:\ExportedVMs\Win11-25H2.vhd"
$resourceGroupName = "rg-win11-images"
$location = "eastus"
$storageAccountName = "win11vhdstorage$(Get-Random -Maximum 9999)"
$containerName = "vhds"
$blobName = "Win11-25H2.vhd"
$imageName = "Win11-25H2-Image"

# Verify VHD file exists
if (-not (Test-Path -Path $vhdPath)) {
    Write-Error "VHD file not found at: $vhdPath"
    exit 1
}

Write-Host "Starting VHD upload and image creation process..." -ForegroundColor Cyan
Write-Host "VHD Path: $vhdPath" -ForegroundColor Yellow

# Connect to Azure (if not already connected)
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Connecting to Azure..." -ForegroundColor Cyan
        Connect-AzAccount
    } else {
        Write-Host "Already connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    }
} catch {
    Write-Host "Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount
}

# Create Resource Group if it doesn't exist
Write-Host "Checking/Creating Resource Group: $resourceGroupName" -ForegroundColor Cyan
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
    Write-Host "Resource Group created: $resourceGroupName" -ForegroundColor Green
} else {
    Write-Host "Resource Group already exists: $resourceGroupName" -ForegroundColor Green
}

# Create Storage Account
Write-Host "Creating Storage Account: $storageAccountName" -ForegroundColor Cyan
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroupName `
        -Name $storageAccountName `
        -Location $location `
        -SkuName Standard_LRS `
        -Kind StorageV2
    Write-Host "Storage Account created: $storageAccountName" -ForegroundColor Green
} else {
    Write-Host "Storage Account already exists: $storageAccountName" -ForegroundColor Green
}

# Get Storage Account Context
$storageContext = $storageAccount.Context

# Create Container if it doesn't exist
Write-Host "Checking/Creating Container: $containerName" -ForegroundColor Cyan
$container = Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container) {
    New-AzStorageContainer -Name $containerName -Context $storageContext -Permission Off
    Write-Host "Container created: $containerName" -ForegroundColor Green
} else {
    Write-Host "Container already exists: $containerName" -ForegroundColor Green
}

# Upload VHD to Azure Storage
Write-Host "Uploading VHD to Azure Storage (this may take a while)..." -ForegroundColor Cyan
$vhdUri = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

try {
    Add-AzVhd -ResourceGroupName $resourceGroupName `
        -Destination $vhdUri `
        -LocalFilePath $vhdPath `
        -OverWrite
    Write-Host "VHD uploaded successfully to: $vhdUri" -ForegroundColor Green
} catch {
    Write-Error "Failed to upload VHD: $_"
    exit 1
}

# Create Managed Image from VHD
Write-Host "Creating Managed Image: $imageName" -ForegroundColor Cyan

$imageConfig = New-AzImageConfig -Location $location -HyperVGeneration V2
$imageConfig = Set-AzImageOsDisk -Image $imageConfig `
    -OsType Windows `
    -OsState Generalized `
    -BlobUri $vhdUri

try {
    $image = New-AzImage -ResourceGroupName $resourceGroupName `
        -ImageName $imageName `
        -Image $imageConfig
    
    Write-Host "`nImage created successfully!" -ForegroundColor Green
    Write-Host "Image Name: $imageName" -ForegroundColor Yellow
    Write-Host "Resource Group: $resourceGroupName" -ForegroundColor Yellow
    Write-Host "Image ID: $($image.Id)" -ForegroundColor Yellow
} catch {
    Write-Error "Failed to create image: $_"
    exit 1
}

Write-Host "`nProcess completed successfully!" -ForegroundColor Green
Write-Host "You can now use this image to create VMs or Windows 365 Cloud PCs" -ForegroundColor Cyan
