<#
.SYNOPSIS
  Pre-flight checks to run BEFORE terraform apply.
  About half of the 23 errors in this lab were environment constraints these
  checks would have caught: quota, regional capacity, identity, and leftover policy.

.EXAMPLE
  .\scripts\preflight-checks.ps1 -Location centralus
#>
param(
    [string]$Location = "centralus",
    [string[]]$Sizes = @("Standard_D4als_v7", "Standard_D16as_v7", "Standard_E2bds_v5"),
    [int]$VcpusNeeded = 20
)

Write-Host "`n== Identities ==" -ForegroundColor Cyan
aws sts get-caller-identity --output table
az account show --query "{subscription:name, tenant:tenantId, user:user.name}" -o table

Write-Host "`n== Regional vCPU quota in $Location (need ~$VcpusNeeded) ==" -ForegroundColor Cyan
Write-Host "Count every VM, helper appliances included. The replication appliance alone is 16 vCPUs."
az vm list-usage --location $Location -o table |
    Select-String -Pattern "Total Regional vCPUs|Standard Dasv7|Standard Dalsv7|Standard EBDSv5"

Write-Host "`n== Are the sizes available in $Location? (Restrictions should be None) ==" -ForegroundColor Cyan
foreach ($size in $Sizes) {
    az vm list-skus --location $Location --size $size --all -o table
}

Write-Host "`n== Leftover Azure Policy assignments (a previous lab's policy blocked this one) ==" -ForegroundColor Cyan
az policy assignment list --query "[].{name:name, displayName:displayName, scope:scope}" -o table

Write-Host "`n== Security Defaults (blocks device-code sign-in for the appliances, error 530035) ==" -ForegroundColor Cyan
Write-Host "Check: Entra ID > Overview > Properties > Manage security defaults."
Write-Host "The appliances also reject personal Microsoft accounts. Plan a directory account up front."

Write-Host "`n== Network path ==" -ForegroundColor Cyan
Write-Host "No VPN between AWS and Azure means push install can't reach the EC2 private IP."
Write-Host "Plan to install the Mobility agent by hand (scripts/install-mobility-agent.ps1)."
