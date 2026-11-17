<#
.SYNOPSIS
  Tear down BOTH clouds the same day. This lab bills on AWS and Azure at once.
  Stop replication in Azure Migrate first, or the vault refuses to delete.
#>
param([string]$Name = "yourname")

# 1. AWS: everything here was built by Terraform
Push-Location "$PSScriptRoot\..\terraform\aws-side"
terraform destroy          # expect: 14 destroyed
Pop-Location

# 2. Azure: use az, not terraform. Both groups now hold things Terraform didn't
#    create (migrated VM, Migrate project, Migrate's own vault).
az group delete --name "rg-migrate-target-$Name" --yes
az group delete --name "rg-migrate-source-$Name" --yes

# 3. Clear Terraform's memory of the Azure side
Push-Location "$PSScriptRoot\..\terraform\azure-side"
terraform destroy
Pop-Location

# 4. Manual, don't skip:
#    - AWS IAM: deactivate + delete the Terraform user's access key; delete the .csv
#    - Entra ID: delete the temporary directory admin account (it had Owner)
#    - Entra ID: confirm Security Defaults is back ON
#    - Next day: check Azure Cost Management and AWS Billing for anything still charging
az group list -o table     # only NetworkWatcherRG should remain
