#Requires -Version 7.0

<#
.SYNOPSIS
Conditionally skips Stage AIML if no changes detected from the previous successful deployment.

.DESCRIPTION
This script compares the current deployment artifacts/code against the previously deployed
version. If no changes are detected in the AIML-related components, it skips Stage AIML
to optimize the pipeline execution time.

.PARAMETER PipelineName
The name of the Release pipeline (default: 'Release-Orchestrator')

.PARAMETER StageName
The stage to conditionally skip (default: 'Stage AIML')

.PARAMETER ArtifactPath
Path to the artifact directory to check for changes

.PARAMETER PreviousDeploymentHash
Hash of the previous successful deployment for comparison

.EXAMPLE
./skip-aiml-stage.ps1 -ArtifactPath './aiml-artifact' -PreviousDeploymentHash 'abc123'
#>

param(
    [string]$PipelineName = 'Release-Orchestrator',
    [string]$StageName = 'Stage AIML',
    [string]$ArtifactPath = './artifacts/aiml',
    [string]$PreviousDeploymentHash = $env:PREVIOUS_DEPLOYMENT_HASH,
    [string]$CurrentDeploymentHash = $env:BUILD_SOURCEVERSION
)

function Get-DirectoryHash {
    <#
    .SYNOPSIS
    Calculates SHA256 hash of a directory's contents for change detection.
    #>
    param(
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path)) {
        Write-Warning "Artifact path not found: $Path"
        return $null
    }
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -File | 
                 Sort-Object -Property FullName
        
        $hashProvider = [System.Security.Cryptography.SHA256]::Create()
        $combinedHash = ""
        
        foreach ($file in $files) {
            $fileStream = [System.IO.File]::OpenRead($file.FullName)
            $fileHash = $hashProvider.ComputeHash($fileStream)
            $fileStream.Close()
            
            $combinedHash += [BitConverter]::ToString($fileHash).Replace("-", "")
        }
        
        $finalHash = $hashProvider.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($combinedHash))
        return [BitConverter]::ToString($finalHash).Replace("-", "")
    }
    catch {
        Write-Error "Error calculating directory hash: $_"
        return $null
    }
}

function Get-LastSuccessfulDeploymentHash {
    <#
    .SYNOPSIS
    Retrieves the hash from the last successful AIML stage deployment.
    Queries Azure DevOps REST API for deployment history.
    #>
    param(
        [string]$Organization,
        [string]$Project,
        [string]$ReleaseId,
        [string]$StageName
    )
    
    try {
        $apiUrl = "https://vsrm.dev.azure.com/$Organization/$Project/_apis/release/releases/$ReleaseId/environments?api-version=7.0"
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Authentication Basic -Token (ConvertTo-SecureString -String $env:SYSTEM_ACCESSTOKEN -AsPlainText -Force)
        
        $lastSuccessfulStage = $response.value | 
                               Where-Object { $_.name -eq $StageName -and $_.deploySteps.status -eq "succeeded" } |
                               Sort-Object -Property modifiedOn -Descending |
                               Select-Object -First 1
        
        if ($lastSuccessfulStage) {
            Write-Host "Last successful deployment: $($lastSuccessfulStage.modifiedOn)"
            return $lastSuccessfulStage.variables | Where-Object { $_.name -eq "AIML_HASH" }
        }
        
        return $null
    }
    catch {
        Write-Warning "Could not retrieve last deployment hash from Azure DevOps: $_"
        return $null
    }
}

function Compare-Deployments {
    <#
    .SYNOPSIS
    Compares current and previous deployment hashes to determine if changes exist.
    #>
    param(
        [string]$CurrentHash,
        [string]$PreviousHash
    )
    
    if ([string]::IsNullOrWhiteSpace($PreviousHash)) {
        Write-Host "No previous deployment hash found. Stage will execute."
        return $true
    }
    
    if ($CurrentHash -eq $PreviousHash) {
        Write-Host "✓ No changes detected: Current hash matches previous deployment."
        return $false
    }
    
    Write-Host "✗ Changes detected: Current hash differs from previous deployment."
    return $true
}

function Disable-PipelineStage {
    <#
    .SYNOPSIS
    Disables the specified stage in the Azure DevOps pipeline.
    #>
    param(
        [string]$Organization,
        [string]$Project,
        [string]$ReleaseId,
        [string]$StageName
    )
    
    try {
        Write-Host "Disabling stage: $StageName"
        
        # Set pipeline variable to skip stage
        Write-Host "##vso[task.setvariable variable=SKIP_${StageName};]true"
        
        # Alternative: Skip job via task command
        Write-Host "##vso[task.logdetail id=$StageName;type=Skipped;]Stage skipped due to no changes detected"
        
        Write-Host "Stage '$StageName' has been marked to skip."
        return $true
    }
    catch {
        Write-Error "Failed to disable stage: $_"
        return $false
    }
}

# Main execution
Write-Host "================================================"
Write-Host "Azure DevOps Release Stage Skip Logic"
Write-Host "Pipeline: $PipelineName"
Write-Host "Stage: $StageName"
Write-Host "================================================"

Write-Host "`nStep 1: Calculate current deployment hash..."
$currentHash = Get-DirectoryHash -Path $ArtifactPath

if ($null -eq $currentHash) {
    Write-Host "ERROR: Could not calculate current deployment hash. Allowing stage to execute."
    exit 1
}

Write-Host "Current AIML artifact hash: $currentHash"

Write-Host "`nStep 2: Retrieve previous deployment hash..."
# If not provided via environment variable, attempt to query Azure DevOps
if ([string]::IsNullOrWhiteSpace($PreviousDeploymentHash)) {
    Write-Host "Querying Azure DevOps for previous deployment hash..."
    $org = $env:SYSTEM_COLLECTIONURI -replace 'https://dev.azure.com/', ''
    $project = $env:SYSTEM_TEAMPROJECT
    $releaseId = $env:RELEASE_RELEASEID
    
    $previousHash = Get-LastSuccessfulDeploymentHash -Organization $org -Project $project -ReleaseId $releaseId -StageName $StageName
} else {
    $previousHash = $PreviousDeploymentHash
}

if ($previousHash) {
    Write-Host "Previous AIML artifact hash: $previousHash"
} else {
    Write-Host "No previous hash available (first deployment or retrieval failed)."
}

Write-Host "`nStep 3: Compare hashes..."
$shouldExecuteStage = Compare-Deployments -CurrentHash $currentHash -PreviousHash $previousHash

Write-Host "`nStep 4: Conditionally disable stage..."
if (-not $shouldExecuteStage) {
    Write-Host "NO CHANGES DETECTED - Skipping $StageName"
    Disable-PipelineStage -Organization $org -Project $project -ReleaseId $releaseId -StageName $StageName
    
    # Store current hash for next deployment
    Write-Host "##vso[task.setvariable variable=AIML_HASH;isOutput=true;]$currentHash"
    
    exit 0
} else {
    Write-Host "CHANGES DETECTED - $StageName will execute normally"
    
    # Store current hash for next deployment
    Write-Host "##vso[task.setvariable variable=AIML_HASH;isOutput=true;]$currentHash"
    
    exit 0
}
