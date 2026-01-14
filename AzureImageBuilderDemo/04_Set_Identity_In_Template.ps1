# Check and fix managed identity in template

$resourceGroupName = "ImageBuilder-rg"

Write-Host "Checking for existing managed identities..."
$identities = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

if ($identities) {
    $identity = $identities | Where-Object { $_.Name -like "aibBuiUserId*" } | Sort-Object -Property Name -Descending | Select-Object -First 1
    
    if ($identity) {
        Write-Host "Found managed identity: $($identity.Name)" -ForegroundColor Green
        Write-Host "Identity Resource ID: $($identity.Id)"
        
        # Update the template with the correct identity
        Write-Host "`nUpdating Win11ImageTemplate.json with correct identity..."
        
        $templatePath = "Win11ImageTemplate.json"
        if (Test-Path $templatePath) {
            $template = Get-Content -Path $templatePath -Raw | ConvertFrom-Json
            
            # Update the identity section
            $template.identity.userAssignedIdentities = @{
                "$($identity.Id)" = @{}
            }
            
            $template | ConvertTo-Json -Depth 100 | Set-Content -Path $templatePath
            
            Write-Host "Template updated successfully!" -ForegroundColor Green
            Write-Host "`nYou can now run: 05_Create_Image_Configuration.ps1"
        } else {
            Write-Host "Template file not found. Run 04_Download_Image_Configuration_Template.ps1 first." -ForegroundColor Red
        }
    } else {
        Write-Host "No managed identity found with name pattern 'aibBuiUserId*'" -ForegroundColor Red
        Write-Host "Please run: 03_Create_User_Assigned_Managed_Identity.ps1" -ForegroundColor Yellow
    }
} else {
    Write-Host "No managed identities found in resource group: $resourceGroupName" -ForegroundColor Red
    Write-Host "Please run: 03_Create_User_Assigned_Managed_Identity.ps1" -ForegroundColor Yellow
}
