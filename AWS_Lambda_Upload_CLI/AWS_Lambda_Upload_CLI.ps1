
# Batch update Lambda functions (unzip and upload from AWS_Lambda_Upload.zip)

# The region must be the same as the one where AWS Lambda is located.
$region = "us-east-1"
# Maximum retry count
$maxRetries = 2
# Interval in seconds between retries
$retryDelay = 10

# Directory containing the script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (-not $scriptDir) {
    # Use the current directory directly
    $scriptDir = Get-Location
}

# Path to compressed archive
$zipArchive = Join-Path $scriptDir "AWS_Lambda_Upload_CLI.zip"

# Temporary extraction directory
$extractDir = Join-Path $scriptDir "AWS_Lambda_Upload_CLI"

# Log directory
$logDir = Join-Path $scriptDir "AWS_Lambda_Upload_CLI_LOG"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

# Timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$resultFile = Join-Path $logDir "AWSupload_CLI_Result_$timestamp.txt"

# Check whether the compressed file exists
if (-not (Test-Path $zipArchive)) {
    Write-Host "Zip archive not found: $zipArchive" -ForegroundColor Red
    exit
}

# If the temporary extraction directory exists, delete it first.
if (Test-Path $extractDir) {
    Remove-Item -Recurse -Force $extractDir
}

# Extract AWS_Lambda_Upload_CLI.zip
Write-Host "Extracting $zipArchive to $extractDir ..."
Expand-Archive -Path $zipArchive -DestinationPath $extractDir -Force

# Initialise the results list
$successList = @()
$failedList  = @()

# Traverse all ZIP files within the extraction directory (including subdirectories)
Get-ChildItem "$extractDir\*.zip" -Recurse | ForEach-Object {
    $funcName = $_.BaseName
    $zipPath = $_.FullName

    $attempt = 1
    $success = $false

    while (-not $success -and $attempt -le $maxRetries) {
        Write-Host "Updating Lambda: $funcName (Attempt $attempt of $maxRetries) ..." -ForegroundColor Yellow
    
        try {
            # Execute AWS CLI commands
            aws lambda update-function-code `
                --function-name $funcName `
                --zip-file fileb://$($zipPath) `
                --region $region `
                --output text
            
            # Check whether the previous command succeeded
            if ($LASTEXITCODE -ne 0) {
                throw "AWS CLI return error code: $LASTEXITCODE"
            }
            
            Write-Host "Successfully updated Lambda: $funcName" -ForegroundColor Green
            $successList += $funcName
            $success = $true

        } catch {
            # Capture errors and log failed items
            Write-Host "Failed to update Lambda: $funcName (Attempt $attempt)" -ForegroundColor Red
            if ($attempt -lt $maxRetries) {
                Write-Host "Retrying in $retryDelay seconds..." -ForegroundColor Cyan
                Start-Sleep -Seconds $retryDelay
            } else {
                Write-Host "Max retries reached. Recording failure." -ForegroundColor Red
                $failedList += $funcName
            }
            $attempt++
        }
    }
}

# Upload complete. Delete the compressed file and extracted directory.
Remove-Item $zipArchive -Force
Remove-Item $extractDir -Recurse -Force
Write-Host "Temporary files cleaned up."

# Output results to the same file, with success and failure separated by ===
Add-Content -Path $resultFile -Value "=== Successfully Uploaded ==="
$successList | ForEach-Object { Add-Content -Path $resultFile -Value $_ }

Add-Content -Path $resultFile -Value ""
Add-Content -Path $resultFile -Value "=== Failed to Upload ==="
$failedList | ForEach-Object { Add-Content -Path $resultFile -Value $_ }

Write-Host "Update finished. Results are recorded in: $resultFile"