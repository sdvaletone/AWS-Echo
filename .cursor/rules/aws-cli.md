# AWS CLI Rules

## Always Check AWS CLI Documentation

When writing AWS CLI commands in PowerShell scripts, ALWAYS:

1. **Reference Official AWS CLI Documentation**
   - Check: https://docs.aws.amazon.com/cli/latest/reference/ec2/index.html
   - Verify command syntax, parameters, and output formats
   - Ensure commands are current and supported

2. **Command Validation Requirements**
   - Verify the exact command name exists in AWS CLI
   - Check parameter names and formats
   - Validate output format options (json, text, table)
   - Confirm filter syntax and query expressions

3. **Common AWS CLI Commands for VPC Endpoints**
   - `aws ec2 describe-regions` - Get available regions
   - `aws ec2 describe-vpcs` - Get VPCs in region
   - `aws ec2 describe-vpc-endpoints` - Get VPC endpoints
   - `aws ec2 describe-vpc-endpoint-services` - Get available services

4. **Output Format Standards**
   - Use `--output json` for structured data
   - Use `--query` for filtering specific fields
   - Use `--filters` for filtering results
   - Handle errors with `2>$null` for PowerShell

5. **Error Handling**
   - Always check `$LASTEXITCODE` after AWS CLI commands
   - Provide meaningful error messages
   - Handle cases where AWS CLI is not available

6. **Documentation Links**
   - EC2 Commands: https://docs.aws.amazon.com/cli/latest/reference/ec2/index.html
   - VPC Endpoints: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-vpc-endpoints.html
   - Regions: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-regions.html

## Example Command Validation Process

Before using any AWS CLI command:

1. Check if command exists in AWS CLI documentation
2. Verify parameter syntax
3. Test output format options
4. Validate filter/query expressions
5. Ensure proper error handling

## Prohibited Practices

- Using undocumented or deprecated commands
- Guessing command syntax without verification
- Using incorrect parameter names or formats
- Ignoring error handling for AWS CLI calls
