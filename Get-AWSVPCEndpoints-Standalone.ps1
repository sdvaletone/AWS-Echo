# Get-AWSVPCEndpoints-Standalone.ps1
# AWS VPC Endpoints Information Script - Standalone Version for PowerShell 7.5.0

#Requires -Version 7.5.0
#Requires -Modules AWS.Tools.Common, AWS.Tools.EC2

<#
.SYNOPSIS
    Standalone AWS VPC Endpoints catalog script for offline instances.

.DESCRIPTION
    This script retrieves and catalogs all VPC endpoints across all VPCs in all AWS regions.
    It generates detailed reports showing endpoint types, services, policies, and groups them by VPC.
    All functionality is self-contained with no external dependencies.

.PARAMETER OutputPath
    Base path where output files will be saved. Defaults to "C:\admin\Get-AWSVPCEndpoints-Standalone".

.PARAMETER OutputFormat
    Output format(s). Can be CSV, JSON, HTML, or All. Defaults to All.

.PARAMETER Regions
    Specific AWS regions to scan. If not specified, all regions will be scanned.

.PARAMETER VpcIds
    Specific VPC IDs to scan. If not specified, all VPCs will be scanned.

.PARAMETER EndpointTypes
    Specific endpoint types to include. Can be Gateway, Interface, or both. Defaults to both.

.PARAMETER Services
    Specific AWS services to include. If not specified, all services are included.

.PARAMETER IncludeDefaultVPC
    Include default VPCs in the scan. Defaults to true.

.PARAMETER ExportDetailedPolicies
    Export detailed endpoint policies to separate files. Defaults to true.

.PARAMETER GenerateSummary
    Generate a summary report. Defaults to true.

.EXAMPLE
    .\Get-AWSVPCEndpoints-Standalone.ps1
    Scans all regions and VPCs for endpoints, outputs all formats to C:\admin\Get-AWSVPCEndpoints-Standalone\.

.EXAMPLE
    .\Get-AWSVPCEndpoints-Standalone.ps1 -Regions @("us-east-1", "us-west-2") -EndpointTypes @("Interface")
    Scans specific regions for Interface endpoints only.

.NOTES
    Author: AWS-Echo Project
    Version: 1.0.0
    PowerShell Version: 7.5.0
    Standalone: No external dependencies
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\admin\Get-AWSVPCEndpoints-Standalone",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("CSV", "JSON", "HTML", "All")]
    [string[]]$OutputFormat = @("All"),
    
    [Parameter(Mandatory = $false)]
    [string[]]$Regions,
    
    [Parameter(Mandatory = $false)]
    [string[]]$VpcIds,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Gateway", "Interface")]
    [string[]]$EndpointTypes = @("Gateway", "Interface"),
    
    [Parameter(Mandatory = $false)]
    [string[]]$Services,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDefaultVPC = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$ExportDetailedPolicies = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$GenerateSummary = $true
)

# =============================================================================
# GLOBAL VARIABLES AND INITIALIZATION
# =============================================================================

# Set strict mode for better error handling
Set-StrictMode -Version Latest

# Global variables
$script:StartTime = Get-Date
$script:TotalEndpoints = 0
$script:TotalVPCs = 0
$script:TotalRegions = 0
$script:LogPath = Join-Path $OutputPath "Logs"
$script:NetworkData = @{
    Summary = @{}
    VPCs = @{}
    Endpoints = @()
    DetailedPolicies = @()
    Regions = @()
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Initialize logging directory and set up logging.
#>
function Initialize-Logging {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $script:LogPath)) {
            New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
            Write-Verbose "Created logging directory: $($script:LogPath)"
        }
        Write-Verbose "Logging initialized with path: $($script:LogPath)"
    }
    catch {
        Write-Error "Failed to initialize logging: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Write a log entry with timestamp.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "VERBOSE")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARNING" { Write-Warning $Message }
        "VERBOSE" { Write-Verbose $Message }
        default { Write-Information $Message }
    }
    
    # Write to log file
    if (-not $LogFile) {
        $LogFile = "VPCEndpoints-$(Get-Date -Format 'yyyy-MM-dd').log"
    }
    
    $logFilePath = Join-Path $script:LogPath $LogFile
    
    try {
        Add-Content -Path $logFilePath -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

# =============================================================================
# AWS CONNECTIVITY FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Test AWS connectivity and credentials.
#>
function Test-AWSConnectivity {
    [CmdletBinding()]
    param(
        [string]$Region = "us-east-1"
    )
    
    try {
        Write-Log "Testing AWS connectivity to region: $Region" -Level VERBOSE
        
        # Test by getting caller identity
        $identity = Get-STSCallerIdentity -Region $Region -ErrorAction Stop
        
        Write-Log "AWS connectivity successful. Account: $($identity.Account), User: $($identity.Arn)" -Level INFO
        return $true
    }
    catch {
        Write-Log "AWS connectivity test failed: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

<#
.SYNOPSIS
    Get all AWS regions.
#>
function Get-AWSRegions {
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Retrieving AWS regions" -Level VERBOSE
        
        $regions = Get-EC2Region | Where-Object { $_.RegionName -ne "us-gov-west-1" -and $_.RegionName -ne "us-gov-east-1" }
        
        Write-Log "Retrieved $($regions.Count) AWS regions" -Level INFO
        return $regions
    }
    catch {
        Write-Log "Failed to retrieve AWS regions: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Get all VPCs in a specific region.
#>
function Get-AWSVPCs {
    [CmdletBinding()]
    param(
        [string]$Region
    )
    
    try {
        $params = @{}
        if ($Region) {
            $params.Region = $Region
        }
        
        Write-Log "Retrieving VPCs from region: $(if($Region) { $Region } else { 'current' })" -Level VERBOSE
        
        $vpcs = Get-EC2Vpc @params
        
        Write-Log "Retrieved $($vpcs.Count) VPCs" -Level INFO
        return $vpcs
    }
    catch {
        Write-Log "Failed to retrieve VPCs: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Get VPC endpoints in a specific region.
#>
function Get-AWSVPCEndpoints {
    [CmdletBinding()]
    param(
        [string]$Region,
        [string]$VpcId,
        [string]$EndpointType
    )
    
    try {
        $params = @{}
        if ($Region) {
            $params.Region = $Region
        }
        if ($VpcId) {
            $params.Filter = @{Name = "vpc-id"; Values = @($VpcId)}
        }
        if ($EndpointType) {
            $params.Filter = @{Name = "vpc-endpoint-type"; Values = @($EndpointType.ToLower())}
        }
        
        Write-Log "Retrieving VPC endpoints from region: $(if($Region) { $Region } else { 'current' })" -Level VERBOSE
        
        $endpoints = Get-EC2VpcEndpoint @params
        
        Write-Log "Retrieved $($endpoints.Count) VPC endpoints" -Level INFO
        return $endpoints
    }
    catch {
        Write-Log "Failed to retrieve VPC endpoints: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# =============================================================================
# DATA PROCESSING FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Get VPC endpoint policy details.
#>
function Get-VPCEndpointPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Endpoint
    )
    
    $policies = @()
    
    try {
        if ($Endpoint.PolicyDocument) {
            $policyData = [PSCustomObject]@{
                EndpointId = $Endpoint.VpcEndpointId
                EndpointName = if ($Endpoint.Tags) { ($Endpoint.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
                VpcId = $Endpoint.VpcId
                ServiceName = $Endpoint.ServiceName
                PolicyType = "Resource Policy"
                PolicyDocument = $Endpoint.PolicyDocument
                PolicySummary = ""
                CreatedDate = $Endpoint.CreationTimestamp
            }
            
            # Try to parse policy document for summary
            try {
                $policyJson = $Endpoint.PolicyDocument | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($policyJson -and $policyJson.Statement) {
                    $policyData.PolicySummary = "Contains $($policyJson.Statement.Count) statement(s)"
                }
            }
            catch {
                $policyData.PolicySummary = "Policy document present but not JSON format"
            }
            
            $policies += $policyData
        }
        
        # Check for additional policy information
        if ($Endpoint.PrivateDnsEnabled) {
            $dnsPolicy = [PSCustomObject]@{
                EndpointId = $Endpoint.VpcEndpointId
                EndpointName = if ($Endpoint.Tags) { ($Endpoint.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
                VpcId = $Endpoint.VpcId
                ServiceName = $Endpoint.ServiceName
                PolicyType = "DNS Configuration"
                PolicyDocument = "Private DNS Enabled: $($Endpoint.PrivateDnsEnabled)"
                PolicySummary = "Private DNS resolution enabled"
                CreatedDate = $Endpoint.CreationTimestamp
            }
            $policies += $dnsPolicy
        }
    }
    catch {
        Write-Log "Error processing policies for endpoint $($Endpoint.VpcEndpointId): $($_.Exception.Message)" -Level WARNING
    }
    
    return $policies
}

<#
.SYNOPSIS
    Process VPC endpoints for a specific VPC.
#>
function Process-VPCEndpoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Vpc,
        
        [Parameter(Mandatory = $true)]
        [string]$Region
    )
    
    try {
        Write-Log "Processing VPC endpoints for VPC: $($Vpc.VpcId) in region: $Region" -Level INFO
        
        # Get VPC endpoints for this VPC
        $endpoints = Get-AWSVPCEndpoints -Region $Region -VpcId $Vpc.VpcId
        
        # Filter by endpoint types if specified
        if ($EndpointTypes) {
            $endpoints = $endpoints | Where-Object { $_.VpcEndpointType -in $EndpointTypes }
        }
        
        # Filter by services if specified
        if ($Services) {
            $endpoints = $endpoints | Where-Object { $_.ServiceName -in $Services }
        }
        
        $vpcData = [PSCustomObject]@{
            VpcId = $Vpc.VpcId
            VpcName = if ($Vpc.Tags) { ($Vpc.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
            CidrBlock = $Vpc.CidrBlock
            State = $Vpc.State
            IsDefault = $Vpc.IsDefault
            Region = $Region
            EndpointCount = $endpoints.Count
            Endpoints = @()
        }
        
        foreach ($endpoint in $endpoints) {
            $endpointData = [PSCustomObject]@{
                EndpointId = $endpoint.VpcEndpointId
                EndpointName = if ($endpoint.Tags) { ($endpoint.Tags | Where-Object { $_.Key -eq "Name" }).Value } else { "N/A" }
                ServiceName = $endpoint.ServiceName
                VpcId = $endpoint.VpcId
                VpcEndpointType = $endpoint.VpcEndpointType
                State = $endpoint.State
                Region = $Region
                CreationTimestamp = $endpoint.CreationTimestamp
                PrivateDnsEnabled = $endpoint.PrivateDnsEnabled
                RequireAcceptance = $endpoint.RequireAcceptance
                PolicyDocument = if ($endpoint.PolicyDocument) { "Present" } else { "None" }
                RouteTableIds = if ($endpoint.RouteTableIds) { $endpoint.RouteTableIds -join ", " } else { "N/A" }
                SubnetIds = if ($endpoint.SubnetIds) { $endpoint.SubnetIds -join ", " } else { "N/A" }
                NetworkInterfaceIds = if ($endpoint.NetworkInterfaceIds) { $endpoint.NetworkInterfaceIds -join ", " } else { "N/A" }
                DnsEntries = if ($endpoint.DnsEntries) { $endpoint.DnsEntries.Count } else { 0 }
                Tags = if ($endpoint.Tags) { $endpoint.Tags } else { @() }
            }
            
            $vpcData.Endpoints += $endpointData
            $script:NetworkData.Endpoints += $endpointData
            
            # Get detailed policies if requested
            if ($ExportDetailedPolicies) {
                $policies = Get-VPCEndpointPolicies -Endpoint $endpoint
                foreach ($policy in $policies) {
                    $policy.Region = $Region
                    $script:NetworkData.DetailedPolicies += $policy
                }
            }
            
            $script:TotalEndpoints++
        }
        
        $script:NetworkData.VPCs[$Vpc.VpcId] = $vpcData
        $script:TotalVPCs++
        
        Write-Log "Processed VPC $($Vpc.VpcId): $($endpoints.Count) VPC endpoints" -Level INFO
    }
    catch {
        Write-Log "Error processing VPC endpoints for VPC $($Vpc.VpcId): $($_.Exception.Message)" -Level ERROR
    }
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

<#
.SYNOPSIS
    Export data to CSV file.
#>
function Export-DataToCSV {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [switch]$Append
    )
    
    try {
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        if ($Append) {
            $Data | Export-Csv -Path $FilePath -Append -NoTypeInformation
        } else {
            $Data | Export-Csv -Path $FilePath -NoTypeInformation
        }
        
        Write-Log "Data exported to CSV: $FilePath" -Level INFO
    }
    catch {
        Write-Log "Failed to export data to CSV: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Export data to JSON file.
#>
function Export-DataToJSON {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [switch]$Compress
    )
    
    try {
        $directory = Split-Path $FilePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        if ($Compress) {
            $json = $Data | ConvertTo-Json -Compress
        } else {
            $json = $Data | ConvertTo-Json -Depth 10
        }
        
        $json | Out-File -FilePath $FilePath -Encoding UTF8
        
        Write-Log "Data exported to JSON: $FilePath" -Level INFO
    }
    catch {
        Write-Log "Failed to export data to JSON: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

<#
.SYNOPSIS
    Generate HTML report for VPC endpoints.
#>
function New-VPCEndpointHTMLReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    try {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AWS VPC Endpoints Report - Standalone</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background: linear-gradient(135deg, #232f3e 0%, #146eb4 100%); color: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .summary { background-color: white; padding: 20px; margin: 20px 0; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .vpc-section { margin: 20px 0; border: 1px solid #ddd; border-radius: 10px; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .vpc-header { background: linear-gradient(135deg, #146eb4 0%, #0f4c75 100%); color: white; padding: 15px; font-weight: bold; border-radius: 10px 10px 0 0; }
        .vpc-content { padding: 20px; }
        .endpoint-table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        .endpoint-table th, .endpoint-table td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        .endpoint-table th { background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); font-weight: 600; }
        .endpoint-table tr:nth-child(even) { background-color: #f8f9fa; }
        .endpoint-table tr:hover { background-color: #e3f2fd; }
        .policy-table { width: 100%; border-collapse: collapse; margin: 15px 0; font-size: 13px; }
        .policy-table th, .policy-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        .policy-table th { background: linear-gradient(135deg, #e3f2fd 0%, #bbdefb 100%); }
        .gateway { background-color: #e8f5e8; border-left: 4px solid #4caf50; }
        .interface { background-color: #fff3e0; border-left: 4px solid #ff9800; }
        .timestamp { color: #666; font-size: 14px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .stat-card { background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat-number { font-size: 2em; font-weight: bold; color: #146eb4; }
        .stat-label { color: #666; margin-top: 5px; }
        .service-badge { background-color: #146eb4; color: white; padding: 4px 8px; border-radius: 12px; font-size: 12px; }
        .type-badge { padding: 4px 8px; border-radius: 12px; font-size: 12px; font-weight: bold; }
        .gateway-badge { background-color: #4caf50; color: white; }
        .interface-badge { background-color: #ff9800; color: white; }
    </style>
</head>
<body>
    <div class="header">
        <h1>AWS VPC Endpoints Report - Standalone</h1>
        <p class="timestamp">Generated on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>PowerShell 7.5.0 | AWS-Echo Project | Standalone Script</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">$($script:TotalRegions)</div>
                <div class="stat-label">Regions Scanned</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($script:TotalVPCs)</div>
                <div class="stat-label">VPCs with Endpoints</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($script:TotalEndpoints)</div>
                <div class="stat-label">Total Endpoints</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($script:NetworkData.DetailedPolicies.Count)</div>
                <div class="stat-label">Policy Documents</div>
            </div>
        </div>
        <p><strong>Scan Duration:</strong> $((Get-Date) - $script:StartTime)</p>
        <p><strong>Endpoint Types:</strong> $($EndpointTypes -join ', ')</p>
        <p><strong>Output Location:</strong> $OutputPath</p>
    </div>
"@

        # Add VPC sections
        foreach ($vpcId in $script:NetworkData.VPCs.Keys) {
            $vpc = $script:NetworkData.VPCs[$vpcId]
            
            $html += @"
    <div class="vpc-section">
        <div class="vpc-header">
            VPC: $($vpc.VpcName) ($($vpc.VpcId)) - $($vpc.Region)
        </div>
        <div class="vpc-content">
            <p><strong>CIDR Block:</strong> $($vpc.CidrBlock)</p>
            <p><strong>State:</strong> $($vpc.State)</p>
            <p><strong>Default VPC:</strong> $($vpc.IsDefault)</p>
            <p><strong>VPC Endpoints:</strong> $($vpc.EndpointCount)</p>
            
            <h3>VPC Endpoints</h3>
            <table class="endpoint-table">
                <tr>
                    <th>Endpoint ID</th>
                    <th>Name</th>
                    <th>Service</th>
                    <th>Type</th>
                    <th>State</th>
                    <th>Private DNS</th>
                    <th>Policy</th>
                    <th>Created</th>
                </tr>
"@
            
            foreach ($endpoint in $vpc.Endpoints) {
                $typeClass = if ($endpoint.VpcEndpointType -eq "Gateway") { "gateway" } else { "interface" }
                $typeBadgeClass = if ($endpoint.VpcEndpointType -eq "Gateway") { "gateway-badge" } else { "interface-badge" }
                
                $html += @"
                <tr class="$typeClass">
                    <td>$($endpoint.EndpointId)</td>
                    <td>$($endpoint.EndpointName)</td>
                    <td><span class="service-badge">$($endpoint.ServiceName)</span></td>
                    <td><span class="type-badge $typeBadgeClass">$($endpoint.VpcEndpointType)</span></td>
                    <td>$($endpoint.State)</td>
                    <td>$($endpoint.PrivateDnsEnabled)</td>
                    <td>$($endpoint.PolicyDocument)</td>
                    <td>$($endpoint.CreationTimestamp.ToString('yyyy-MM-dd HH:mm'))</td>
                </tr>
"@
            }
            
            $html += @"
            </table>
        </div>
    </div>
"@
        }
        
        # Add detailed policies section if available
        if ($ExportDetailedPolicies -and $script:NetworkData.DetailedPolicies.Count -gt 0) {
            $html += @"
    <div class="vpc-section">
        <div class="vpc-header">Detailed VPC Endpoint Policies</div>
        <div class="vpc-content">
            <table class="policy-table">
                <tr>
                    <th>Endpoint</th>
                    <th>VPC</th>
                    <th>Region</th>
                    <th>Service</th>
                    <th>Policy Type</th>
                    <th>Summary</th>
                    <th>Created</th>
                </tr>
"@
            
            foreach ($policy in $script:NetworkData.DetailedPolicies) {
                $html += @"
                <tr>
                    <td>$($policy.EndpointName)<br/>($($policy.EndpointId))</td>
                    <td>$($policy.VpcId)</td>
                    <td>$($policy.Region)</td>
                    <td><span class="service-badge">$($policy.ServiceName)</span></td>
                    <td>$($policy.PolicyType)</td>
                    <td>$($policy.PolicySummary)</td>
                    <td>$($policy.CreatedDate.ToString('yyyy-MM-dd HH:mm'))</td>
                </tr>
"@
            }
            
            $html += @"
            </table>
        </div>
    </div>
"@
        }
        
        $html += @"
</body>
</html>
"@
        
        $html | Out-File -FilePath $FilePath -Encoding UTF8
        Write-Log "HTML report generated: $FilePath" -Level INFO
    }
    catch {
        Write-Log "Error generating HTML report: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-Log "Starting AWS VPC Endpoints standalone scan" -Level INFO
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level INFO
    Write-Log "Output path: $OutputPath" -Level INFO
    Write-Log "Output formats: $($OutputFormat -join ', ')" -Level INFO
    Write-Log "Endpoint types: $($EndpointTypes -join ', ')" -Level INFO
    
    # Initialize logging
    Initialize-Logging
    
    # Test AWS connectivity
    if (-not (Test-AWSConnectivity)) {
        Write-Error "AWS connectivity test failed. Please check your credentials and configuration."
        exit 1
    }
    
    # Determine regions to scan
    if ($Regions) {
        $regionsToScan = $Regions
        Write-Log "Scanning specific regions: $($Regions -join ', ')" -Level INFO
    } else {
        $regionsToScan = (Get-AWSRegions).RegionName
        Write-Log "Scanning all available regions: $($regionsToScan.Count) regions" -Level INFO
    }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-Log "Created output directory: $OutputPath" -Level INFO
    }
    
    # Process each region
    foreach ($region in $regionsToScan) {
        try {
            Write-Log "Processing region: $region" -Level INFO
            
            # Get VPCs in this region
            $vpcs = Get-AWSVPCs -Region $region
            
            # Filter VPCs if specific VPCs requested
            if ($VpcIds) {
                $vpcs = $vpcs | Where-Object { $_.VpcId -in $VpcIds }
            }
            
            # Filter default VPCs if requested
            if (-not $IncludeDefaultVPC) {
                $vpcs = $vpcs | Where-Object { -not $_.IsDefault }
            }
            
            $script:NetworkData.Regions += $region
            $script:TotalRegions++
            
            # Process each VPC
            foreach ($vpc in $vpcs) {
                Process-VPCEndpoints -Vpc $vpc -Region $region
            }
            
            Write-Log "Completed region: $region" -Level INFO
        }
        catch {
            Write-Log "Error processing region $region`: $($_.Exception.Message)" -Level ERROR
            continue
        }
    }
    
    # Generate summary
    if ($GenerateSummary) {
        $script:NetworkData.Summary = [PSCustomObject]@{
            ScanDate = Get-Date
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            TotalRegions = $script:TotalRegions
            TotalVPCs = $script:TotalVPCs
            TotalEndpoints = $script:TotalEndpoints
            TotalPolicies = $script:NetworkData.DetailedPolicies.Count
            ScanDuration = (Get-Date) - $script:StartTime
            Regions = $script:NetworkData.Regions
            EndpointTypes = $EndpointTypes
            Services = if ($Services) { $Services } else { @("All") }
            OutputPath = $OutputPath
        }
    }
    
    # Export data based on requested formats
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    if ($OutputFormat -contains "All" -or $OutputFormat -contains "CSV") {
        # Export endpoints to CSV
        $csvPath = Join-Path $OutputPath "VPCEndpoints_Detailed_Report_$timestamp.csv"
        Export-DataToCSV -Data $script:NetworkData.Endpoints -FilePath $csvPath
        
        # Export detailed policies to CSV if available
        if ($ExportDetailedPolicies -and $script:NetworkData.DetailedPolicies.Count -gt 0) {
            $policiesCsvPath = Join-Path $OutputPath "VPCEndpointPolicies_Detailed_Report_$timestamp.csv"
            Export-DataToCSV -Data $script:NetworkData.DetailedPolicies -FilePath $policiesCsvPath
        }
        
        # Export summary to CSV if available
        if ($GenerateSummary) {
            $summaryCsvPath = Join-Path $OutputPath "VPCEndpoints_Summary_Report_$timestamp.csv"
            Export-DataToCSV -Data @($script:NetworkData.Summary) -FilePath $summaryCsvPath
        }
    }
    
    if ($OutputFormat -contains "All" -or $OutputFormat -contains "JSON") {
        # Export complete data to JSON
        $jsonPath = Join-Path $OutputPath "VPCEndpoints_Complete_Data_$timestamp.json"
        Export-DataToJSON -Data $script:NetworkData -FilePath $jsonPath
    }
    
    if ($OutputFormat -contains "All" -or $OutputFormat -contains "HTML") {
        # Generate HTML report
        $htmlPath = Join-Path $OutputPath "VPCEndpoints_Comprehensive_Report_$timestamp.html"
        New-VPCEndpointHTMLReport -FilePath $htmlPath
    }
    
    # Final summary
    $duration = (Get-Date) - $script:StartTime
    Write-Log "VPC endpoints scan completed successfully" -Level INFO
    Write-Log "Total regions scanned: $($script:TotalRegions)" -Level INFO
    Write-Log "Total VPCs with endpoints: $($script:TotalVPCs)" -Level INFO
    Write-Log "Total VPC endpoints: $($script:TotalEndpoints)" -Level INFO
    Write-Log "Total policies: $($script:NetworkData.DetailedPolicies.Count)" -Level INFO
    Write-Log "Scan duration: $duration" -Level INFO
    Write-Log "Output files saved to: $OutputPath" -Level INFO
    
    # Display summary to console
    Write-Host "`n=== AWS VPC Endpoints Standalone Scan Complete ===" -ForegroundColor Green
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host "Regions Scanned: $($script:TotalRegions)" -ForegroundColor Yellow
    Write-Host "VPCs with Endpoints: $($script:TotalVPCs)" -ForegroundColor Yellow
    Write-Host "Total VPC Endpoints: $($script:TotalEndpoints)" -ForegroundColor Yellow
    Write-Host "Total Policies: $($script:NetworkData.DetailedPolicies.Count)" -ForegroundColor Yellow
    Write-Host "Duration: $duration" -ForegroundColor Yellow
    Write-Host "Output Location: $OutputPath" -ForegroundColor Yellow
    Write-Host "=================================================`n" -ForegroundColor Green
}
catch {
    Write-Log "Fatal error during VPC endpoints scan: $($_.Exception.Message)" -Level ERROR
    Write-Error "VPC endpoints scan failed: $($_.Exception.Message)"
    exit 1
}
