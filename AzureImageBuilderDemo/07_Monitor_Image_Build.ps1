# Monitor Image Builder build progress

$resourceGroupName = "ImageBuilder-rg"
$templateName = "Win11ImageTemplate"

Write-Host "Monitoring Image Builder build progress for: $templateName" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop monitoring (build will continue in background)`n"

$checkInterval = 30 # seconds
$iteration = 0

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    $template = Get-AzResource `
        -ResourceGroupName $resourceGroupName `
        -ResourceType "Microsoft.VirtualMachineImages/imageTemplates" `
        -ResourceName $templateName `
        -ErrorAction SilentlyContinue
    
    if ($null -eq $template) {
        Write-Host "[$timestamp] Template not found!" -ForegroundColor Red
        break
    }
    
    $lastRunStatus = $template.Properties.lastRunStatus
    
    if ($null -eq $lastRunStatus) {
        Write-Host "[$timestamp] Build has not started yet. Waiting..." -ForegroundColor Yellow
    } else {
        $runState = $lastRunStatus.runState
        $runSubState = $lastRunStatus.runSubState
        $message = $lastRunStatus.message
        
        Write-Host "[$timestamp] Run State: $runState | Sub State: $runSubState" -ForegroundColor Cyan
        
        if ($message) {
            Write-Host "  Message: $message" -ForegroundColor Gray
        }
        
        if ($runState -eq "Succeeded") {
            Write-Host "`n✓ Image build completed successfully!" -ForegroundColor Green
            Write-Host "`nOutput image details:"
            $template.Properties.lastRunStatus.outputImages | Format-Table
            break
        } elseif ($runState -eq "Failed" -or $runState -eq "Canceled") {
            Write-Host "`n✗ Image build $runState" -ForegroundColor Red
            if ($lastRunStatus.provisioningError) {
                Write-Host "`nError Details:" -ForegroundColor Red
                $lastRunStatus.provisioningError | ConvertTo-Json -Depth 5
            }
            break
        }
    }
    
    Write-Host "  Waiting $checkInterval seconds before next check... (Iteration: $iteration)"
    Start-Sleep -Seconds $checkInterval
}

Write-Host "`nMonitoring stopped."
