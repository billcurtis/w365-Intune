# Start the Image Builder build process

$resourceGroupName = "ImageBuilder-rg"
$templateName = "Win11ImageTemplate"

Write-Host "Checking template status..."

# Wait for template to be ready
$timeout = 600 # 10 minutes
$elapsed = 0
$interval = 15

while ($elapsed -lt $timeout) {
    $template = Get-AzResource `
        -ResourceGroupName $resourceGroupName `
        -ResourceType "Microsoft.VirtualMachineImages/imageTemplates" `
        -ResourceName $templateName `
        -ErrorAction SilentlyContinue
    
    if ($null -eq $template) {
        Write-Host "`nTemplate not found. Please run 05_Create_Image_Configuration.ps1 first." -ForegroundColor Red
        exit 1
    }
    
    $provisioningState = $template.Properties.provisioningState
    Write-Host "Provisioning State: $provisioningState"
    
    if ($provisioningState -eq "Succeeded") {
        Write-Host "`nTemplate is ready!" -ForegroundColor Green
        break
    } elseif ($provisioningState -eq "Failed") {
        Write-Host "`nTemplate creation failed. Check errors with Check_Template_Status.ps1" -ForegroundColor Red
        exit 1
    } elseif ($provisioningState -eq "Creating") {
        Write-Host "Waiting for template creation to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    } else {
        Write-Host "Current state: $provisioningState. Waiting..." -ForegroundColor Yellow
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }
}

if ($elapsed -ge $timeout) {
    Write-Host "`nTimeout reached waiting for template to be ready." -ForegroundColor Red
    exit 1
}

Write-Host "`nStarting image build for template: $templateName"
Write-Host "This process may take 30-60 minutes to complete..."

Invoke-AzResourceAction `
    -ResourceGroupName $resourceGroupName `
    -ResourceType "Microsoft.VirtualMachineImages/imageTemplates" `
    -ResourceName $templateName `
    -Action "Run" `
    -Force

Write-Host "Image build started successfully!"
