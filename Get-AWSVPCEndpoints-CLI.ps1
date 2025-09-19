# Get-AWSVPCEndpoints-CLI.ps1
# Simple AWS VPC Endpoints Catalog using AWS CLI - PowerShell 7.5.0

#Requires -Version 7.5.0

<#
.SYNOPSIS
    Simple AWS VPC Endpoints catalog using AWS CLI.

.DESCRIPTION
    Scans all VPC endpoints across all VPCs in all AWS regions using AWS CLI commands.
    Outputs simple CSV reports. No external PowerShell modules required.

.PARAMETER OutputPath
    Base path where output files will be saved. Defaults to "C:\admin\Get-AWSVPCEndpoints-CLI".

.PARAMETER Regions
    Specific AWS regions to scan. If not specified, all regions will be scanned.

.PARAMETER EndpointTypes
    Specific endpoint types to include. Can be Gateway, Interface, or both. Defaults to both.

.PARAMETER Services
    Specific AWS services to include. If not specified, all services are included.

.EXAMPLE
    .\Get-AWSVPCEndpoints-CLI.ps1
    Scans all regions and VPCs for endpoints, outputs CSV to C:\admin\Get-AWSVPCEndpoints-CLI\.

.EXAMPLE
    .\Get-AWSVPCEndpoints-CLI.ps1 -Regions @("us-east-1") -EndpointTypes @("Interface")
    Scans only us-east-1 region for Interface endpoints.

.NOTES
    Author: AWS-Echo Project
    Version: 1.0.0
    PowerShell Version: 7.5.0
    Dependencies: AWS CLI only
    Authentication: IAM Profile
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\admin\Get-AWSVPCEndpoints-CLI",
    
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
# AWS CLI FUNCTIONS
# =============================================================================

function Test-AWSConnection {
    try {
        # Simple test by trying to get regions
        $result = aws ec2 describe-regions --query "Regions[0].RegionName" --output text 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-SimpleLog "AWS CLI connection successful"
            return $true
        }
        else {
            Write-SimpleLog "ERROR: AWS CLI connection failed"
            return $false
        }
    }
    catch {
        Write-SimpleLog "ERROR: AWS CLI not available or connection failed"
        return $false
    }
}

function Get-AWSRegions {
    try {
        $result = aws ec2 describe-regions --query "Regions[].RegionName" --output text 2>$null
        if ($LASTEXITCODE -eq 0) {
            $regions = $result -split "`t" | Where-Object { $_ -ne "us-gov-west-1" -and $_ -ne "us-gov-east-1" -and $_ -ne "" }
            return $regions
        }
        else {
            Write-SimpleLog "ERROR: Failed to get regions"
            return @()
        }
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
        $cmd = "aws ec2 describe-vpc-endpoints --region $Region"
        if ($VpcId) {
            $cmd += " --filters Name=vpc-id,Values=$VpcId"
        }
        
        $result = Invoke-Expression $cmd 2>$null
        if ($LASTEXITCODE -eq 0) {
            $endpoints = $result | ConvertFrom-Json
            return $endpoints.VpcEndpoints
        }
        else {
            Write-SimpleLog "ERROR: Failed to get VPC endpoints in $Region"
            return @()
        }
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
        $result = aws ec2 describe-vpcs --region $Region --output json 2>$null
        if ($LASTEXITCODE -eq 0) {
            $vpcs = $result | ConvertFrom-Json
            return $vpcs.Vpcs
        }
        else {
            Write-SimpleLog "ERROR: Failed to get VPCs in $Region"
            return @()
        }
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
    
    # Extract tags
    $tags = "None"
    if ($Endpoint.Tags) {
        $tagPairs = $Endpoint.Tags | ForEach-Object { "$($_.Key)=$($_.Value)" }
        $tags = $tagPairs -join "; "
    }
    
    # Extract name from tags
    $endpointName = "N/A"
    if ($Endpoint.Tags) {
        $nameTag = $Endpoint.Tags | Where-Object { $_.Key -eq "Name" }
        if ($nameTag) {
            $endpointName = $nameTag.Value
        }
    }
    
    # Format arrays
    $routeTableIds = if ($Endpoint.RouteTableIds) { $Endpoint.RouteTableIds -join "; " } else { "N/A" }
    $subnetIds = if ($Endpoint.SubnetIds) { $Endpoint.SubnetIds -join "; " } else { "N/A" }
    $networkInterfaceIds = if ($Endpoint.NetworkInterfaceIds) { $Endpoint.NetworkInterfaceIds -join "; " } else { "N/A" }
    $dnsEntries = if ($Endpoint.DnsEntries) { $Endpoint.DnsEntries.Count } else { 0 }
    
    $endpointData = [PSCustomObject]@{
        Region = $Region
        VpcId = $Endpoint.VpcId
        VpcName = $VpcName
        EndpointId = $Endpoint.VpcEndpointId
        EndpointName = $endpointName
        ServiceName = $Endpoint.ServiceName
        EndpointType = $Endpoint.VpcEndpointType
        State = $Endpoint.State
        CreatedDate = $Endpoint.CreationTimestamp
        PrivateDnsEnabled = $Endpoint.PrivateDnsEnabled
        HasPolicy = if ($Endpoint.PolicyDocument) { "Yes" } else { "No" }
        RouteTableIds = $routeTableIds
        SubnetIds = $subnetIds
        NetworkInterfaceIds = $networkInterfaceIds
        DnsEntryCount = $dnsEntries
        Tags = $tags
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

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-SimpleLog "Starting AWS VPC Endpoints CLI Scan"
    Write-SimpleLog "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-SimpleLog "Output Path: $OutputPath"
    Write-SimpleLog "Endpoint Types: $($EndpointTypes -join ', ')"
    
    # Test AWS CLI connection
    if (-not (Test-AWSConnection)) {
        Write-Error "AWS CLI connection failed. Please check your IAM profile and AWS CLI installation."
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
                # Extract VPC name from tags
                $vpcName = "N/A"
                if ($vpc.Tags) {
                    $nameTag = $vpc.Tags | Where-Object { $_.Key -eq "Name" }
                    if ($nameTag) {
                        $vpcName = $nameTag.Value
                    }
                }
                
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
    $csvPath = Join-Path $OutputPath "VPCEndpoints_$timestamp.csv"
    Export-ToCSV -Data $script:AllEndpoints -FilePath $csvPath
    
    # Final summary
    $duration = (Get-Date) - $script:StartTime
    Write-SimpleLog "Scan completed successfully"
    Write-SimpleLog "Regions scanned: $($script:TotalRegions)"
    Write-SimpleLog "VPCs with endpoints: $($script:TotalVPCs)"
    Write-SimpleLog "Total endpoints found: $($script:TotalEndpoints)"
    Write-SimpleLog "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-SimpleLog "Output location: $OutputPath"
    
    # Display summary to console
    Write-Host "`n=== AWS VPC Endpoints CLI Scan Complete ===" -ForegroundColor Green
    Write-Host "Regions: $($script:TotalRegions) | VPCs: $($script:TotalVPCs) | Endpoints: $($script:TotalEndpoints)" -ForegroundColor Yellow
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss')) | Output: $OutputPath" -ForegroundColor Yellow
    Write-Host "=============================================`n" -ForegroundColor Green
}
catch {
    Write-SimpleLog "FATAL ERROR: $($_.Exception.Message)"
    Write-Error "VPC endpoints scan failed: $($_.Exception.Message)"
    exit 1
}
