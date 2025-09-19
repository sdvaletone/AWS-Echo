# AWS-Echo Project Rules

## Project Overview
AWS-Echo is a collection of PowerShell scripts for AWS network information cataloging, specifically focused on VPC endpoints.

## Core Requirements

### PowerShell Version
- **ALWAYS** target PowerShell 7.5.0
- Use `#Requires -Version 7.5.0` in all scripts
- No external PowerShell modules allowed

### Dependencies
- **ONLY** AWS CLI and PowerShell
- **NO** external PowerShell modules (AWS.Tools.*, ImportExcel, etc.)
- Authentication via IAM profile only

### Output Requirements
- **ALWAYS** output to `C:\admin\$SCRIPT_NAME\$Descriptive_Filename_for_output`
- Use descriptive filenames with timestamps
- Prefer CSV format for simplicity
- No complex HTML or JSON reports

### AWS CLI Commands
- **ALWAYS** check AWS CLI documentation before writing commands
- Reference: https://docs.aws.amazon.com/cli/latest/reference/ec2/index.html
- Use proper error handling with `$LASTEXITCODE`
- Validate command syntax and parameters

### Script Structure
- Single, self-contained .ps1 files
- No external file dependencies
- Simple logging to console only
- Minimal, essential functions only

### VPC Endpoints Focus
- Target VPC endpoints for AWS services
- Catalog: ID, name, service, type, state, policies
- Group by VPC for organized reporting
- Support filtering by regions, types, services

### Offline Execution
- Designed for completely offline instances
- No internet connectivity required
- Self-contained with all dependencies bundled

## Prohibited Practices
- Using external PowerShell modules
- Complex output formats (HTML, JSON)
- External file dependencies
- Guessing AWS CLI command syntax
- Using deprecated or undocumented commands

## Required Documentation
- Always reference AWS CLI docs for commands
- Include usage examples in script comments
- Document all parameters and outputs
- Provide clear error messages
