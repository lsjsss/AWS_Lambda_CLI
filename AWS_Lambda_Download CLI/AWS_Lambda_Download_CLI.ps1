# Lambda Batch Download

# Specify AWS Region
$region = "us-east-1"
# Local output folder
$outputDir = ".\AWS_Lambda_Download"
# Maximum retry count
$maxRetries = 2
# Retry interval (seconds)
$retryDelay = 10

# Directory containing the script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if (-not $scriptDir) {
    # Use the current directory directly
    $scriptDir = Get-Location
}

# Lambda function list file
$listFile = Join-Path $scriptDir "AWS_Lambda_Download_List.txt"

if (-not (Test-Path $listFile)) {
    # If no TXT file exists, download all functions (retrieve the list of Lambda functions).
    Write-Host "LambdaDownloadList.txt not found in script directory: $scriptDir" -ForegroundColor Red
    $functionsJson = aws lambda list-functions --region $region --output json | ConvertFrom-Json
    $functions = $functionsJson.Functions | ForEach-Object { $_.FunctionName }
} else {
    Write-Host "Fetching Lambda function list from region: $region ..." -ForegroundColor Cyan
    # Read the list of function names (one function name per line, ignoring blank lines and comment lines)
    $functions = Get-Content $listFile | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
}
Write-Host "functions : $functions" -ForegroundColor Red

if (-not $functions) {
    Write-Host "No Lambda functions found or failed to list." -ForegroundColor Red
    exit
}

# If the output folder does not exist, create it.
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Initialisation failure log file
$failedFile = Join-Path $outputDir "AWS_Lambda_Download_Failed.txt"
if (Test-Path $failedFile) { Remove-Item $failedFile }

foreach ($funcName in $functions) {

    $attempt = 1
    $success = $false

    while (-not $success -and $attempt -le $maxRetries) {
        Write-Host "Downloading Lambda: $funcName (Attempt $attempt of $maxRetries) ..." -ForegroundColor Yellow
        try {
            # Obtain the download URL for the Lambda function code
            $url = aws lambda get-function `
                --function-name $funcName `
                --region $region `
                --query 'Code.Location' `
                --output text

            if (-not $url) { throw "Failed to get code location." }

            # Download the zip file
            $zipPath = Join-Path $outputDir "$funcName.zip"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -MaximumRedirection 10 -Headers @{ "User-Agent" = "Mozilla/5.0" }

            # Verify whether the file size is reasonable
            $fileInfo = Get-Item $zipPath
            if ($fileInfo.Length -lt 1000) {   
                # throw "Downloaded file too small."
                Write-Warning "Downloaded file for $funcName is smaller than 1KB. It may be empty or minimal code."
            }

            Write-Host "Successfully saved: $zipPath" -ForegroundColor Green
            $success = $true
        }
        catch {
            Write-Host "Failed to download: $funcName (Attempt $attempt)" -ForegroundColor Red
            if ($attempt -lt $maxRetries) {
                Write-Host "Retrying in $retryDelay seconds..." -ForegroundColor Cyan
                Start-Sleep -Seconds $retryDelay
            }
            else {
                Write-Host "Max retries reached. Recording failure." -ForegroundColor Red
                Add-Content -Path $failedFile -Value $funcName
            }
            $attempt++
        }
    }
}

# Compress the download directory and delete the original directory.
$zipFile = Join-Path $scriptDir "AWS_Lambda_Download.zip"

# If the ZIP file already exists, delete it first.
if (Test-Path $zipFile) {
    Remove-Item $zipFile -Force
    Write-Host "Existing ZIP file deleted: $zipFile" -ForegroundColor Yellow
}

if (Test-Path $zipFile) { Remove-Item $zipFile -Force }

Compress-Archive -Path "$outputDir\*" -DestinationPath $zipFile -Force
Write-Host "All downloaded Lambda functions have been zipped to $zipFile" -ForegroundColor Green

Remove-Item -Path $outputDir -Recurse -Force
Write-Host "Original download folder $outputDir has been deleted." -ForegroundColor Green

Write-Host "All downloads completed."
Write-Host "Failed items (if any) are recorded in: $failedFile"