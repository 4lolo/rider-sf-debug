$currentDir = $PSScriptRoot

# Variables

# Find path to rider
$riderPath = (Get-Process -Name rider64).Path

# Find path to .sln file
$solutionPath = (Get-ChildItem -Path (Join-Path -Path $currentDir -ChildPath "..") -Filter *.sln -Recurse -Depth 1).FullName

# Find path to .sfproj file
$projectPath = (Get-ChildItem -Path (Join-Path -Path $currentDir -ChildPath "..") -Filter *.sfproj -Recurse -Depth 2).FullName

# Find path to SF scripts (usually Scripts folder next to .sfproj file)
$scriptsPath = Join-Path -Path (Split-Path -Path $projectPath -Parent) -ChildPath "Scripts"

# Resolve application name (name of the .sfproj file without extension)
$applicationName = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)

# Resolve application type (for me "$($applicationName)Type")
$applicationTypeName = "$($applicationName)Type"

# Resolve process name (for me "$($applicationName).Web")
$processName = "$($applicationName).Web"

# Import SF module
Import-Module 'C:\Program Files\Microsoft SDKs\Service Fabric\Tools\PSModule\ServiceFabricSDK\ServiceFabricSDK.psm1'; 

# Package project
& dotnet build "-t:Package" "-c:Debug" "-p:Platform=x64" "-p:Deterministic=true" """$projectPath"""

try {
    Push-Location $scriptsPath

    # Connect to cluster
    Write-Host "[Deploy] Connecting to cluster..."
    if (-not (Connect-ServiceFabricCluster)) {
        throw "Unable to connect to Cluster"
    }
    # Share connection to avoid errors
    $global:ClusterConnection = $ClusterConnection
    Write-Host "[Deploy] Connecting to cluster... done"

    # Check if application exists; if yes - remove it
    Write-Host "[Deploy] Checking for existing application..."
    $sfApplication = Get-ServiceFabricApplication -ApplicationName "fabric:/$applicationName"
    if ($sfApplication -ne $null) {
        Write-Host "[Deploy] Checking for existing application... removing old version"
        Remove-ServiceFabricApplication -ApplicationName $sfApplication.ApplicationName -ForceRemove -Force
        Write-Host "[Deploy] Checking for existing application... done"
    } else {
        Write-Host "[Deploy] Checking for existing application... not found"
    }

    # Check if application type exists; if yes - remove it
    Write-Host "[Deploy] Checking for existing application type..."
    $sfApplicationType = Get-ServiceFabricApplicationType -ApplicationTypeName $applicationTypeName
    if ($sfApplicationType -ne $null) {
        Write-Host "[Deploy] Checking for existing application type... removing old version"
        Remove-ServiceFabricApplicationType -ApplicationTypeName $sfApplicationType.ApplicationTypeName -ApplicationTypeVersion $sfApplicationType.ApplicationTypeVersion
        Write-Host "[Deploy] Checking for existing application type... done"
    } else {
        Write-Host "[Deploy] Checking for existing application type... not found"
    }

    # Deploy
    Write-Host "[Deploy] Deploying application..."
    .\Deploy-FabricApplication.ps1 -ApplicationPackagePath '..\pkg\Debug' -PublishProfileFile "..\PublishProfiles\Local.1Node.xml" -DeployOnly:$false -ApplicationParameter:@{} -UnregisterUnusedApplicationVersionsAfterUpgrade $true -OverrideUpgradeBehavior 'None' -OverwriteBehavior 'Always' -SkipPackageValidation:$false -ErrorAction Stop -UseExistingClusterConnection
    Write-Host "[Deploy] Deploying application... done"
    
    Get-ServiceFabricApplicationStatus -ApplicationName "fabric:/$applicationName" -ErrorAction Stop

    # Look for process to resolve process id
    Write-Host "[Deploy] Looking for process..."
    $process = $null
    $processRetry = 10
    while ($process -eq $null -and $processRetry-- -gt 0) {
        Start-Sleep -Seconds 2
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    }
    if ($process -ne $null) {
        Write-Host "[Deploy] Looking for process... done"
    } else {
        Write-Host "[Deploy] Looking for process... not found"
    }
        
    # If process was found - start rider with attach-to-process option
    if ($process -ne $null) {
        & $riderPath attach-to-process $process.Id """$solutionPath"""
    }
} finally {
    Pop-Location
}