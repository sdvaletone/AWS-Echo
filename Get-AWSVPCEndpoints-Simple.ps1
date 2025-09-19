# Get-AWSVPCEndpoints-Simple.ps1
# Simple AWS VPC Endpoints Catalog - PowerShell 7.5.0

#Requires -Version 7.5.0
#Requires -Modules AWS.Tools.Common, AWS.Tools.EC2

<#
.SYNOPSIS
    Simple AWS VPC Endpoints catalog script.

.DESCRIPTION
    Scans all VPC endpoints across all VPCs in all AWS regions and outputs simple CSV/XLSX reports.

.PARAMETER OutputPath
    Base path where output files will be saved. Defaults to "C:\admin\Get-AWSVPCEndpoints-Simple".

.PARAMETER OutputFormat
    Output format: CSV, XLSX, or Both. Defaults to Both.

.PARAMETER Regions
    Specific AWS regions to scan. If not specified, all regions will be scanned.

.PARAMETER EndpointTypes
    Specific endpoint types to include. Can be Gateway, Interface, or both. Defaults to both.

.PARAMETER Services
    Specific AWS services to include. If not specified, all services are included.

.EXAMPLE
    .\Get-AWSVPCEndpoints-Simple.ps1
    Scans all regions and VPCs for endpoints, outputs CSV and XLSX to C:\admin\Get-AWSVPCEndpoints-Simple\.

.EXAMPLE
    .\Get-AWSVPCEndpoints-Simple.ps1 -Regions @("us-east-1") -OutputFormat CSV
    Scans only us-east-1 region, outputs only CSV format.

.NOTES
    Author: AWS-Echo Project
    Version: 1.0.0
    PowerShell Version: 7.5.0
    Simple: CSV and XLSX output only
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\admin\Get-AWSVPCEndpoints-Simple",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("CSV", "XLSX", "Both")]
    [string]$OutputFormat = "Both",
    
    [Parameter(Mandatory = $false)]
    [string[]]$Regions,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Gateway", "Interface")]
    [string[]]$EndpointTypes = @("Gateway", "Interface"),
    
    [Parameter(Mandatory = $false)]
    [string[]]$Services
)

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

$script:StartTime = Get-Date
$script:TotalEndpoints = 0
$script:TotalVPCs = 0
$script:TotalRegions = 0
$script:AllEndpoints = @()

# =============================================================================
# SIMPLE LOGGING
# =============================================================================

function Write-SimpleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    Write-Host $logEntry
}

# =============================================================================
# AWS FUNCTIONS
# =============================================================================

function Test-AWSConnection {
    try {
        $identity = Get-STSCallerIdentity -ErrorAction Stop
        Write-SimpleLog "Connected to AWS Account: $($identity.Account)"
        return $true
    }
    catch {
        Write-SimpleLog "ERROR: AWS connection failed - $($_.Exception.Message)"
        return $false
    }
}

function Get-AWSRegions {
    try {
        $regions = Get-EC2Region | Where-Object { $_.RegionName -ne "us-gov-west-1" -and $_.RegionName -ne "us-gov-east-1" }
        return $regions.RegionName
    }
    catch {
        Write-SimpleLog "ERROR: Failed to get regions - $($_.Exception.Message)"
        return @()
    }
}

function Get-VPCEndpoints {
    [CmdletBinding()]
    param(
        [string]$Region,
        [string]$VpcId
    )
    
    try {
        $params = @{}
        if ($Region) { $params.Region = $Region }
        if ($VpcId) { $params.Filter = @{Name = "vpc-id"; Values = @($VpcId)} }
        
        $endpoints = Get-EC2VpcEndpoint @params
        return $endpoints
    }
    catch {
        Write-SimpleLog "ERROR: Failed to get VPC endpoints in $Region - $($_.Exception.Message)"
        return @()
    }
}

function Get-VPCs {
    [CmdletBinding()]
    param(
        [string]$Region
    )
    
    try {
        $params = @{}
        if ($Region) { $params.Region = $Region }
        
        $vpcs = Get-EC2Vpc @params
        return $vpcs
    }
    catch {
        Write-SimpleLog "ERROR: Failed to get VPCs in $Region - $($_.Exception.Message)"
        return @()
    }
}

# =============================================================================
# DATA PROCESSING
# =============================================================================

function Process-Endpoint {
    [CmdletBinding()]
    param(
        [PSObject]$Endpoint,
        [string]$Region,
        [string]$VpcName
    )
    
    # Filter by endpoint types if specified
    if ($EndpointTypes -and $Endpoint.VpcEndpointType -notin $EndpointTypes) {
        return $null
    }
    
    # Filter by services if specified
    if ($Services -and $Endpoint.ServiceName -notin $Services) {
        return $null
    }
    
    $endpointData = [PSCustomObject]@{
        Region = $Region
        VpcId = $Endpoint.VpcId
        VpcName = $VpcName
        EndpointId = $Endpoint.VpcEndpointId
        EndpointName = if ($Endpoint.Tags) { ($Endpoint.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
        ServiceName = $Endpoint.ServiceName
        EndpointType = $Endpoint.VpcEndpointType
        State = $Endpoint.State
        CreatedDate = $Endpoint.CreationTimestamp.ToString('yyyy-MM-dd HH:mm:ss')
        PrivateDnsEnabled = $Endpoint.PrivateDnsEnabled
        HasPolicy = if ($Endpoint.PolicyDocument) { "Yes" } else { "No" }
        RouteTableIds = if ($Endpoint.RouteTableIds) { $Endpoint.RouteTableIds -join "; " } else { "N/A" }
        SubnetIds = if ($Endpoint.SubnetIds) { $Endpoint.SubnetIds -join "; " } else { "N/A" }
        NetworkInterfaceIds = if ($Endpoint.NetworkInterfaceIds) { $Endpoint.NetworkInterfaceIds -join "; " } else { "N/A" }
        DnsEntryCount = if ($Endpoint.DnsEntries) { $Endpoint.DnsEntries.Count } else { 0 }
        Tags = if ($Endpoint.Tags) { ($Endpoint.Tags | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; " } else { "None" }
    }
    
    return $endpointData
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

function Export-ToCSV {
    [CmdletBinding()]
    param(
        [PSObject[]]$Data,
        [string]$FilePath
    )
    
    try {
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        $Data | Export-Csv -Path $FilePath -NoTypeInformation
        Write-SimpleLog "CSV exported: $FilePath"
    }
    catch {
        Write-SimpleLog "ERROR: Failed to export CSV - $($_.Exception.Message)"
    }
}

function Export-ToXLSX {
    [CmdletBinding()]
    param(
        [PSObject[]]$Data,
        [string]$FilePath
    )
    
    try {
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Check if ImportExcel module is available
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel -Force
            $Data | Export-Excel -Path $FilePath -AutoSize -TableStyle Medium2
            Write-SimpleLog "XLSX exported: $FilePath"
        }
        else {
            Write-SimpleLog "WARNING: ImportExcel module not found. Install with: Install-Module ImportExcel"
            Write-SimpleLog "Falling back to CSV format"
            $csvPath = $FilePath -replace '\.xlsx$', '.csv'
            Export-ToCSV -Data $Data -FilePath $csvPath
        }
    }
    catch {
        Write-SimpleLog "ERROR: Failed to export XLSX - $($_.Exception.Message)"
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-SimpleLog "Starting AWS VPC Endpoints Simple Scan"
    Write-SimpleLog "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-SimpleLog "Output Path: $OutputPath"
    Write-SimpleLog "Output Format: $OutputFormat"
    Write-SimpleLog "Endpoint Types: $($EndpointTypes -join ', ')"
    
    # Test AWS connection
    if (-not (Test-AWSConnection)) {
        Write-Error "AWS connection failed. Please check your credentials."
        exit 1
    }
    
    # Determine regions to scan
    if ($Regions) {
        $regionsToScan = $Regions
        Write-SimpleLog "Scanning specific regions: $($Regions -join ', ')"
    } else {
        $regionsToScan = Get-AWSRegions
        Write-SimpleLog "Scanning all regions: $($regionsToScan.Count) regions"
    }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-SimpleLog "Created output directory: $OutputPath"
    }
    
    # Process each region
    foreach ($region in $regionsToScan) {
        try {
            Write-SimpleLog "Processing region: $region"
            
            # Get VPCs in this region
            $vpcs = Get-VPCs -Region $region
            
            foreach ($vpc in $vpcs) {
                $vpcName = if ($vpc.Tags) { ($vpc.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
                
                # Get VPC endpoints for this VPC
                $endpoints = Get-VPCEndpoints -Region $region -VpcId $vpc.VpcId
                
                foreach ($endpoint in $endpoints) {
                    $endpointData = Process-Endpoint -Endpoint $endpoint -Region $region -VpcName $vpcName
                    if ($endpointData) {
                        $script:AllEndpoints += $endpointData
                        $script:TotalEndpoints++
                    }
                }
                
                if ($endpoints.Count -gt 0) {
                    $script:TotalVPCs++
                }
            }
            
            $script:TotalRegions++
            Write-SimpleLog "Completed region: $region"
        }
        catch {
            Write-SimpleLog "ERROR: Failed to process region $region - $($_.Exception.Message)"
            continue
        }
    }
    
    # Export results
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    if ($OutputFormat -eq "CSV" -or $OutputFormat -eq "Both") {
        $csvPath = Join-Path $OutputPath "VPCEndpoints_$timestamp.csv"
        Export-ToCSV -Data $script:AllEndpoints -FilePath $csvPath
    }
    
    if ($OutputFormat -eq "XLSX" -or $OutputFormat -eq "Both") {
        $xlsxPath = Join-Path $OutputPath "VPCEndpoints_$timestamp.xlsx"
        Export-ToXLSX -Data $script:AllEndpoints -FilePath $xlsxPath
    }
    
    # Final summary
    $duration = (Get-Date) - $script:StartTime
    Write-SimpleLog "Scan completed successfully"
    Write-SimpleLog "Regions scanned: $($script:TotalRegions)"
    Write-SimpleLog "VPCs with endpoints: $($script:TotalVPCs)"
    Write-SimpleLog "Total endpoints found: $($script:TotalEndpoints)"
    Write-SimpleLog "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-SimpleLog "Output location: $OutputPath"
    
    # Display summary to console
    Write-Host "`n=== AWS VPC Endpoints Simple Scan Complete ===" -ForegroundColor Green
    Write-Host "Regions: $($script:TotalRegions) | VPCs: $($script:TotalVPCs) | Endpoints: $($script:TotalEndpoints)" -ForegroundColor Yellow
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss')) | Output: $OutputPath" -ForegroundColor Yellow
    Write-Host "===============================================`n" -ForegroundColor Green
}
catch {
    Write-SimpleLog "FATAL ERROR: $($_.Exception.Message)"
    Write-Error "VPC endpoints scan failed: $($_.Exception.Message)"
    exit 1
}
