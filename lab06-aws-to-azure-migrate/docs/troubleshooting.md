# Troubleshooting log: 23 errors and how I fixed them

The lab ran from **Nov 3 to Nov 11, 2026**. Every problem below was real, listed in the order I hit it. Each fix is already built into the Terraform and scripts in this repo.

**Phases:** 0 = local setup · 1 = AWS source · 2 = Azure target · 3 = discovery appliance · 5 = replication · 6 = cutover

| # | Phase | Error | Cause | Fix | Category |
|---|---|---|---|---|---|
| 1 | 0 | `UnauthorizedOperation … explicit deny in a service control policy` | An AWS policy above IAM blocked EC2 calls | New AWS account on the Paid plan, new IAM user and keys | Policy guardrail |
| 2 | 1 | Terraform initialized in an empty directory | Wrong folder, or files saved as `.txt` | `cd` into `aws-side`; check with `Get-ChildItem` | Terraform |
| 3 | 1 | RDP password rejected on EC2 | Special characters broke the first-boot password script | Simple password, then `terraform apply -replace="aws_instance.source_vm"` | Terraform |
| 4 | 1 | `Variables not allowed` in tfvars | Password value had no quotes | Quote every text value in `terraform.tfvars` | Terraform |
| 5 | 2 | Vault already exists … needs to be imported | A half-finished apply | `terraform import` with the ID from the error | Terraform |
| 6 | 2 | `BMSUserErrorDisablingSoftDeleteStateNotAllowed` | New vaults can't turn soft delete off | `soft_delete_enabled = true` | Terraform |
| 7 | 3 | `computer_name` can be at most 15 characters | `vm-mig-appl-<name>` was 17 | `computer_name = "appl-${var.yourname}"` | Terraform |
| 8 | 3 | `RequestDisallowedByPolicy` (Restrict-VM-Sizes) | A previous lab's policy was assigned to the whole subscription | Deleted that policy assignment | Policy guardrail |
| 9 | 3 | 80 GB is smaller than … 127 GB | The Windows image disk is 127 GB | `disk_size_gb = 127` | Capacity & sizing |
| 10 | 3 | Quota limit 0, then `SkuNotAvailable` | Older sizes blocked; East US out of capacity | Moved to Central US; `Standard_D4als_v7` + Gen2 image | Capacity & sizing |
| 11 | 3 | Root object was present, but now absent | Applied while the old resource group was still deleting | Wait for `az group exists` = false, delete local state, apply | Terraform |
| 12 | 3 | RDP password rejected on the appliance | Username needed the local prefix | `.\migrateadmin` | Identity |
| 13 | 3 | "You don't have access to this" at appliance login | Personal (Gmail) Microsoft accounts aren't accepted | Directory user with Owner | Identity |
| 14 | 3 | Sign-in error `530035` | Security Defaults blocks device-code sign-in | Security Defaults off during registration, then back on | Identity |
| 15 | 3 | Access is denied / WinRM cannot complete the operation | Wrong IP in the AWS rule; WinRM limited to local subnet; TrustedHosts | Correct /32 rule, `Enable-PSRemoting`, firewall rule, TrustedHosts, `LocalAccountTokenFilterPolicy` | Networking |
| 16 | 5 | At least 600 GB free space is required | Replication appliance prerequisite | 700 GB OS disk, C: extended | Capacity & sizing |
| 17 | 5 | Only 8 GB of memory … recommend 16 GB | Replication appliance prerequisite | A 16 GB+ size | Capacity & sizing |
| 18 | 5 | Only 2 (then 4) CPU cores … recommend 8 | Sizes run 2 threads per core | `Standard_D16as_v7` after raising quotas to 20 | Capacity & sizing |
| 19 | 5 | Failed to execute … `PS_Configurator.ps1` | Registration failed partway | Kept Security Defaults off until setup finished, then retried | Identity |
| 20 | 5 | Registration wiped | Clicked **Reset appliance** | Restarted W3SVC, cleared Edge cache, restarted the VM, redid setup | Appliance registration |
| 21 | 5 | Server missing from Replicate | Registration not finalized; no physical server added | Finalized from the classic view; added the server with status Success | Appliance registration |
| 22 | 5 | `Mobility service installation failed on the source machine (IP: 10.0.1.78)` | Push install needs the private AWS IP | Installed the agent by hand on EC2 | Networking |
| 23 | 5 | "Protection couldn't be enabled" item left behind | Leftover from the failed push | Cleared, then replicated again with `credentialLessRunAsAccount` | Appliance registration |
| — | 6 | None | — | Test migration, clean-up, cutover; hostname matched | — |

## By category

| Category | Count | Checkable before `terraform apply`? |
|---|---|---|
| Terraform config & state | 7 | No, found while building |
| Capacity, quota & sizing | 5 | **Yes**: quotas, SKU availability, appliance requirements |
| Identity & sign-in | 4 | **Yes**: account type, Security Defaults |
| Appliance registration | 3 | No, found while building |
| Policy guardrails | 2 | **Yes**: SCPs, leftover Azure Policy |
| Networking & WinRM | 2 | Partly: drawing the network path predicts #22 |

**11 of 23** were environment constraints I could have checked up front. That's what [`scripts/preflight-checks.ps1`](../scripts/preflight-checks.ps1) is for.

## Also worth knowing

- The Azure Migrate **Jobs** history shows three `Update Mobility Service` jobs that failed after replication was enabled. Replication stayed **Protected / Healthy** throughout, and the test failover and failover jobs both succeeded.
- Copying text between RDP windows (Ctrl+C / Ctrl+V) worked even when copying files didn't. That's how the Mobility agent's `config.json` got onto the EC2 server.
- Stop the replication appliance from the **portal** (Stopped, deallocated). Shutting it down inside Windows keeps billing for its 16 vCPUs.
