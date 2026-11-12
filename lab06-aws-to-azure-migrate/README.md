# Lab 06: AWS to Azure Migration with Azure Migrate

I moved a running Windows Server from **AWS into Azure** using Azure Migrate, the same tool companies use when they switch clouds. I built both sides with Terraform, then took the server through the four stages of every migration: **discovery, assessment, replication, and cutover**. The server that came up in Azure had the same hostname, the same Windows install, and the same Administrator password as the one in AWS.

It was by far the longest lab so far. I hit 24 problems along the way, and they're all documented [below](#️-problems-i-hit-and-how-i-fixed-them).

| | |
|---|---|
| **Difficulty** | Advanced |
| **Time** | Four sessions: Nov 3, 6, 10, and 11, 2026 (replication to cutover took about 1.5 hours on the last day) |
| **Region** | AWS us-east-1 (source), Azure Central US (target) |
| **Concepts** | Cloud-to-cloud migration, Azure Migrate, discovery and assessment, replication, test migration, cutover, multi-cloud Terraform |

---

## Objective

Build a Windows Server 2022 EC2 instance in AWS and a landing zone in Azure, both with Terraform. Use Azure Migrate to discover and assess the server, replicate its disk into Azure, prove the copy boots with a test migration, cut over for real, log in to the migrated VM, and then tear down both clouds.

## Architecture

```mermaid
flowchart LR
    subgraph AWS["AWS us-east-1"]
        EC2["EC2AMAZ-L2B9ONI<br/>Windows Server 2022<br/>t3.medium"]
        Agent["Mobility agent"]
        EC2 --- Agent
    end

    subgraph Azure["Azure Central US"]
        subgraph Src["rg-migrate-source-shaun"]
            Disc["Discovery appliance<br/>vm-mig-appl-shaun"]
            Repl["Replication appliance<br/>vm-mig-repl-shaun"]
            Cache["Cache storage<br/>stmigrateshaun"]
            Proj["migrate-project-shaun"]
        end
        subgraph Tgt["rg-migrate-target-shaun"]
            VM["Migrated VM<br/>EC2AMAZ-L2B9ONI"]
        end
    end

    Disc -->|"Step 1: WinRM 5985<br/>inventory + performance"| EC2
    Disc -->|reports to| Proj
    Agent -->|"Step 2: disk changes<br/>on 9443"| Repl
    Repl --> Cache
    Cache -->|"Step 3: cutover"| VM
```

Two helper VMs run in Azure, and they're easy to mix up. The **discovery appliance** is the inspector: it logs in to the server and measures it for the assessment. The **replication appliance** is the moving truck: it receives every disk change from the Mobility agent and writes it into Azure. Cutover turns that copy into the new VM.

The AWS VPC (`10.0.0.0/16`) and the Azure VNet (`10.1.0.0/16`) use different ranges on purpose, so they would never overlap if the two networks were ever connected.

## Skills Demonstrated

- Writing **Terraform for two clouds** (`hashicorp/aws` and `hashicorp/azurerm`), in separate folders with separate state
- Translating AWS building blocks into their Azure equivalents (EC2 → VM, VPC → VNet, security group → NSG, EBS → managed disk)
- Deploying and registering the **Azure Migrate discovery appliance** and running agent-based discovery over WinRM
- Reading an **Azure Migrate assessment**: readiness, sizing, and monthly cost
- Deploying the **replication appliance** and installing the **Mobility service agent** by hand
- Running a **test migration** and verifying boot with **Boot diagnostics** when the VM has no public IP
- Performing a **cutover** and proving the migrated server is the same machine
- Working within **vCPU quotas**, SKU restrictions, and leftover policy from an earlier lab
- Tearing down two clouds, including resources Terraform didn't create

## Resources Deployed

| Item | Name | Cloud | Notes |
|---|---|---|---|
| VPC / subnet | `vpc-migrate-shaun` / `snet-migrate-shaun` | AWS | `10.0.0.0/16` / `10.0.1.0/24` |
| Security group | `migrate-source-sg-shaun` | AWS | RDP, HTTPS, plus WinRM/SMB/WMI from the appliance IP only |
| EC2 instance | `ec2-migrate-source-shaun` | AWS | t3.medium, Windows Server 2022, 30 GB gp3. Hostname `EC2AMAZ-L2B9ONI` |
| IAM role, policy, service user | `role-` / `policy-` / `svc-azure-migrate-shaun` | AWS | From the lab guide; not needed in the end |
| Resource groups | `rg-migrate-source-shaun`, `rg-migrate-target-shaun` | Azure | Central US |
| VNet / subnet | `vnet-migrate-shaun` / `snet-migrate` | Azure | `10.1.0.0/16` / `10.1.1.0/24` |
| Replication cache | `stmigrateshaun` | Azure | Standard LRS |
| Log Analytics / vault | `law-migrate-shaun` / `rsv-migrate-shaun` | Azure | Vault has soft delete on |
| Azure Migrate project | `migrate-project-shaun` | Azure | Created in the portal (Terraform can't) |
| Discovery appliance | `vm-mig-appl-shaun` | Azure | Standard_D4als_v7, removed before replication |
| Replication appliance | `vm-mig-repl-shaun` | Azure | Standard_D16as_v7, 700 GB OS disk |
| Migrated VM | `EC2AMAZ-L2B9ONI` | Azure | Plus `pip-migrated-vm` and `nsg-migrate-target-shaun` for RDP |

The Terraform is in [`terraform/aws-side`](./terraform/aws-side) and [`terraform/azure-side`](./terraform/azure-side). Each folder has a `terraform.tfvars.example`; the real `terraform.tfvars` and state files are git-ignored.

---

## Walkthrough

### Phase 1: Build the source server in AWS

Terraform on my own PC (signed in to both clouds) built the VPC, subnet, internet gateway, route table, security group, IAM pieces, and the EC2 instance: **14 resources**.

![terraform apply: 14 added, with EC2 outputs](./docs/screenshots/01-aws-terraform-apply-14-added.png)

The instance came up Running with all status checks passed:

![EC2 instance running, 3/3 checks passed](./docs/screenshots/02-aws-ec2-running-status-checks.png)

I RDP'd in as Administrator to prove it was alive, then turned on WinRM inside it (`Enable-PSRemoting`) so the discovery appliance could log in later.

![RDP session on the EC2 Windows Server](./docs/screenshots/03-aws-ec2-rdp-desktop.png)

### Phase 2: Build the Azure landing zone

A second Terraform folder built the Azure side: two resource groups, the VNet, the replication cache storage account, a Log Analytics workspace, a Recovery Services vault, and an NSG for the migrated VM. **9 resources** at this stage.

![Azure terraform apply: 9 added](./docs/screenshots/04-azure-terraform-apply-9-added.png)
![Source and target resource groups in Central US](./docs/screenshots/05-azure-resource-groups-central-us.png)

Terraform can't create an Azure Migrate project, so I made `migrate-project-shaun` in the portal:

![migrate-project-shaun overview](./docs/screenshots/06-migrate-project-created.png)

### Phase 3: Discovery

I generated a project key for an appliance on a **Physical or other (AWS, GCP, Xen)** source:

![Discover: project key generated for appliance-SW](./docs/screenshots/07-discovery-project-key-generated.png)

Then I built the discovery appliance VM with Terraform and opened **WinRM (5985) on the EC2 security group, only for the appliance's IP**. Terraform changed the security group in place:

![terraform plan: 0 to add, 1 to change for the WinRM rule](./docs/screenshots/08-aws-winrm-rule-1-to-change.png)

Inside the appliance VM I downloaded and ran `AzureMigrateInstaller.ps1`. It finished with one warning about Internet Explorer, which I skipped by opening the Configuration Manager in Edge instead:

![Azure Migrate appliance installer finishing](./docs/screenshots/09-discovery-appliance-installer-complete.png)

I registered the appliance with the project key and signed in to Azure from inside it:

![Signing in to Azure from the discovery appliance](./docs/screenshots/10-discovery-appliance-azure-sign-in.png)

I added the EC2 Windows login (`ec2winadmin`) and the server's IP as a discovery source, then started discovery:

![Discovery successfully initiated](./docs/screenshots/11-discovery-started.png)

The server showed up in the project under its Windows hostname, **EC2AMAZ-L2B9ONI**, not its AWS name tag:

![EC2AMAZ-L2B9ONI in All inventory](./docs/screenshots/12-discovered-server-ec2amaz-l2b9oni.png)

### Phase 4: Assessment

I ran an Azure VM assessment (`assess-aws-ec2`) with performance-based sizing, target Central US, and pay-as-you-go pricing.

![Assessment: 1 Ready, $40.86/month](./docs/screenshots/13-assessment-ready-for-azure.png)

| Result | Value |
|---|---|
| Readiness | **Ready** (1 of 1, nothing to fix) |
| Monthly cost estimate | **$40.86** (compute $23.58, storage $2.40, security $14.88) |
| Support status | Extended |

The assessment's confidence rating depends on how long the appliance has been collecting performance data, and mine had only watched the server for a short time. In a real project you'd let it collect for days or weeks before trusting the sizing.

### Phase 5: Replication

The subscription allows **10 vCPUs per region**, so I commented the discovery appliance out of Terraform and destroyed it before building the replication appliance. The replication appliance ended up on **Standard_D16as_v7**, which needed a vCPU quota increase.

I ran the replication appliance installer, signed in, and registered it with the vault:

![Signing in to Azure from the replication appliance](./docs/screenshots/14-replication-appliance-azure-sign-in.png)
![Replication appliance configuration completed](./docs/screenshots/15-replication-appliance-configured.png)

Then I gave it the EC2 credentials and IP, which validated successfully:

![Physical server credentials and EC2 server validated](./docs/screenshots/16-replication-appliance-server-credentials.png)

The **Mobility agent** is the piece that actually watches the EC2 disk. I installed it by hand on the EC2 server and registered it against the replication appliance with its config file:

![Mobility agent registration completed on the EC2 server](./docs/screenshots/17-mobility-agent-registered-on-ec2.png)

In the Replicate wizard I pointed the copy at `rg-migrate-target-shaun`, `vnet-migrate-shaun`, and `snet-migrate`:

![Replicate: review and start replication](./docs/screenshots/18-replicate-review-start-replication.png)

Initial replication finished and the server reached **Protected / Healthy**:

![EC2AMAZ-L2B9ONI Protected and Healthy](./docs/screenshots/19-replication-protected-healthy.png)

### Phase 6: Test migration, then cutover

A test migration builds a throwaway copy without touching the source. The test VM has no public IP, so instead of RDP I checked **Boot diagnostics**. A Windows lock screen means it booted:

![EC2AMAZ-L2B9ONI-test boot diagnostics showing the lock screen](./docs/screenshots/20-test-migration-boot-diagnostics.png)

I cleaned up the test, then ran the real migration. The Jobs list shows the whole sequence:

![Jobs: enable replication, test failover, cleanup, failover](./docs/screenshots/21-migration-jobs-test-and-failover.png)

| Job | Started | Duration |
|---|---|---|
| Enable replication | 6:42 PM | 8m 34s |
| Test failover | 8:06 PM | 2m 20s |
| Test failover cleanup | 8:13 PM | 1m 08s |
| Failover (cutover) | 8:16 PM | 3m 21s |

The migrated VM landed in the target resource group with its own disk and NIC. It had no public IP or NSG, so I created `pip-migrated-vm` and attached it and `nsg-migrate-target-shaun` to the NIC with the Azure CLI:

![Target resource group: disk, NIC, NSG, public IP](./docs/screenshots/22-target-rg-migrated-vm-resources.png)

Then I RDP'd in with the **same Administrator password I set on EC2**:

![hostname EC2AMAZ-L2B9ONI and winver Windows Server 2022 on the Azure VM](./docs/screenshots/23-migrated-vm-hostname-proof.png)

`hostname` returns **EC2AMAZ-L2B9ONI** and `winver` shows Windows Server 2022. It's the same server, now running in Azure. The EC2 info on the desktop wallpaper is still there, but every field except the hostname is blank, because it can no longer reach AWS's instance metadata.

### Clean-up

I destroyed the AWS side: **14 destroyed**. That also removed the unused `svc-azure-migrate-shaun` IAM user and its access key.

![terraform destroy: 14 destroyed](./docs/screenshots/24-aws-terraform-destroy-14-destroyed.png)

On Azure, both resource groups held things Terraform didn't create (the migrated VM, the Migrate project, Azure Migrate's own resources), so I deleted them with `az group delete` and then ran `terraform destroy` to clear the state. Only `NetworkWatcherRG` is left:

![Only NetworkWatcherRG remains](./docs/screenshots/25-azure-clean-only-networkwatcherrg.png)

---

## ⚠️ Problems I Hit and How I Fixed Them

The lab guide had gaps, and my subscription had limits the guide didn't plan for. These are the 24 problems from my notes and screenshots, roughly in the order I hit them.

### Setup and AWS

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | `az login` showed `AADSTS50076` / "No subscriptions found" | My directory requires MFA and the plain login skipped it | `az login --tenant <tenant ID>` and complete the MFA prompt |
| 2 | `AccessDenied` creating IAM users and policies | The Terraform IAM user only had EC2 and VPC rights | Attached `IAMFullAccess` to `terraform-migrate-lab` |
| 3 | The guide's AMI ID could be out of date | AMI IDs change per region and over time | Looked up the current Windows Server 2022 AMI with `aws ec2 describe-images` |
| 4 | Security group name rejected | AWS reserves the `sg-` prefix | Renamed it `migrate-source-sg-shaun` |

### Azure landing zone

| # | Problem | Cause | Fix |
|---|---|---|---|
| 5 | Missing required provider for `null` | The guide uses `null_resource` without declaring the provider | Added `hashicorp/null` to `required_providers` |
| 6 | `BMSUserErrorDisablingSoftDeleteStateNotAllowed` | New Recovery Services vaults have soft delete locked on | Set `soft_delete_enabled = true` |
| 7 | `appliance_admin_password` undeclared, no `appliance_public_ip` output, wrong VM name in the guide's `az` commands | Gaps in the guide's code | Declared the variable, added the output, used `vm-mig-appl-shaun` |

### Discovery appliance VM (failed six times before it built)

| # | Problem | Cause | Fix |
|---|---|---|---|
| 8 | `computer_name can be at most 15 characters` | `vm-mig-appl-shaun` is 17 | Set `computer_name = "appl-shaun"` |
| 9 | `RequestDisallowedByPolicy` naming `Restrict-VM-Sizes` | **Lab 05's policy was still assigned to the whole subscription** (the scope mistake I documented in Lab 05) | Deleted that assignment under Policy → Assignments |
| 10 | Disk size 80 GB smaller than the image's 127 GB | The Windows Server 2022 image ships a 127 GB disk | `disk_size_gb = 127` |
| 11 | Cores quota exceeded (current limit: 0) | That VM family had no quota on my subscription | Checked `az vm list-usage` and picked a family with quota |
| 12 | `SkuNotAvailable` in East US, then Central US | Older sizes (A4_v2, B4ms, D3_v2) are blocked for my subscription | Moved to Central US and used `Standard_D4als_v7` with the Gen2 image `2022-datacenter-g2` |
| 13 | "Root object was present, but now absent" | I re-applied while the old resource groups were still deleting | Waited until `az group exists` returned false before rebuilding |

### Discovery

| # | Problem | Cause | Fix |
|---|---|---|---|
| 14 | Discovery couldn't log in to the server | No WinRM port open in AWS, and WinRM off inside Windows | Opened 5985 from the appliance IP only and ran `Enable-PSRemoting` on the EC2 |
| 15 | The guide adds AWS access keys as a Windows credential | The appliance logs in to Windows, not to the AWS API | Used only the Windows Administrator login |
| 16 | Appliance installer finished with a warning | The Configuration Manager doesn't support Internet Explorer | Declined IE removal and opened the Configuration Manager in Edge |

### Replication

| # | Problem | Cause | Fix |
|---|---|---|---|
| 17 | Not enough vCPUs for both appliances plus the migrated and test VMs | 10 vCPUs per region: 4 + 4 + 2 + 2 = 12 | Commented out and destroyed the discovery appliance before building the replication appliance |
| 18 | Replication appliance needed more than the quota allowed | I ended up on `Standard_D16as_v7` (16 vCPUs) | Requested a vCPU quota increase |
| 19 | Replication NSG only opened 443 | The Mobility agent sends disk data on 9443 | Added 9443 from the EC2 public IP only |
| 20 | The guide has no Mobility agent step, and its Replicate wizard picks the discovery appliance | AWS servers need the agent; only the replication appliance can receive data | Installed the agent and picked the replication appliance in the wizard |
| 21 | Mobility agent push install | I opened SMB (445), WMI (135), and the dynamic RPC range from the appliance IP for push install | Installed and registered the agent by hand on the EC2 server instead |
| 22 | Three **Update Mobility Service** jobs failed | Not investigated; replication stayed Healthy and both failovers succeeded | Left as is. Next time I'd open the job's error details before cutover |

### Cutover and teardown

| # | Problem | Cause | Fix |
|---|---|---|---|
| 23 | Couldn't RDP into the test VM or the migrated VM | Neither has a public IP, and the guide never attaches the NSG | Boot diagnostics for the test VM; created `pip-migrated-vm` and attached it and the NSG for the real one |
| 24 | `terraform destroy` can't remove the Azure resource groups | They contain resources Terraform didn't create | `az group delete` on both groups, then `terraform destroy` to empty the state |

**The lesson:** most of these weren't Azure Migrate problems at all. They were quotas, SKU restrictions, region availability, and a policy I'd left behind in a previous lab. Problem 9 is the one I'd point to: an assignment with the wrong scope in Lab 05 silently blocked a deployment a month later in Lab 06. Cleaning up policy assignments is part of clean-up, not just deleting resource groups.

---

## Notes and Decisions

- **Region moved from East US to Central US** because the VM sizes I needed weren't available to my subscription in East US.
- **Two Terraform folders**, one per cloud, so each side can be built and destroyed on its own with its own state file.
- **The appliance IPs are variables** (`migrate_appliance_ip`, `ec2_public_ip`) in the committed Terraform, so no real IPs are in the repo. The WinRM rule pointed at the discovery appliance first and the replication appliance later.
- **The discovery appliance is commented out** in `azure-side/main.tf`, matching the state at the end of the lab. As committed, each side builds 14 resources.
- **The IAM service user and access key** come from the lab guide but weren't used. The access key is stored in plain text in the AWS state file, which is one more reason `*.tfstate` is git-ignored.
- **I chose No for "shut down machines before migration."** Fine for a lab with no workload. In production you'd shut the source down to avoid split-brain.
- **The migrated VM's About Windows dialog still says it's licensed to EC2 / Amazon.com.** That's just the registered owner text from the original install; it shows the disk really came across unchanged.
- **The lab took four sessions instead of one.** The guide plans for one 4–6 hour sitting, and both appliance VMs cost money while they run, so finishing in one day is cheaper.
- **Screenshots are redacted.** My AWS account ID, IAM access key ID, Azure subscription ID, email, tenant domain, project key, appliance machine ID, Mobility agent machine details, portal session URLs, and all public IP addresses are blurred.

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `invalid value for name` on the security group | Name starts with `sg-` | Use a name like `migrate-source-sg-<name>` |
| `RequestDisallowedByPolicy` on a VM | A leftover policy assignment | Check Policy → Assignments at subscription scope |
| `SkuNotAvailable` or a quota error | Size blocked or no quota for that family | `az vm list-skus --location centralus --all -o table` and `az vm list-usage --location centralus -o table` |
| Discovery source validation fails | WinRM blocked by the security group or Windows firewall | Check the 5985 rule uses the appliance IP; rerun `Enable-PSRemoting` |
| Server doesn't appear in the Replicate wizard | Mobility agent not registered yet | Register the agent, then allow up to 15 minutes |
| Replication stuck at 0% | Agent missing, or 443/9443 blocked | Confirm the agent is registered; check the replication NSG |
| Can't RDP into the migrated VM | No public IP or NSG on its NIC | Create a public IP and attach it and the NSG with `az network nic` |
| `az group delete` fails on the vault | Replicated items still in the vault | Stop replication, delete replicated items, retry |

## Key Concepts Recap

- **Every migration has four stages:** discovery (what do I have), assessment (will it fit and what will it cost), replication (copy it while it keeps running), and cutover (make the copy the real thing).
- **Discovery appliance vs. replication appliance:** one takes inventory, the other moves the data. They're separate VMs with separate jobs.
- **The Mobility agent** runs on the source server and streams disk changes. AWS and physical servers need it even when the guide calls the migration "agentless."
- **Test migration before cutover.** It proves the VM boots in Azure with zero impact on the source.
- **A migrated VM gets a new IP address.** Anything that pointed at the old one, like DNS records, has to be updated as part of cutover.
- **Quotas and SKU availability are real constraints.** The right VM size on paper doesn't help if your subscription can't deploy it in that region.

## What I Learned

- The migration itself was the easy part. Getting the helper VMs deployed took longer than discovery, assessment, replication, and cutover combined.
- Mistakes in one lab carry into the next. A policy assignment I scoped wrong in Lab 05 blocked deployments here, which made the case for cleaning up governance as carefully as resources.
- Terraform only cleans up what it created. Once Azure Migrate added its own resources, `az group delete` had to do the real teardown.
- Boot diagnostics is the quickest way to check a VM that has no public IP.

## Possible Next Steps

- Investigate the failed **Update Mobility Service** jobs and get them succeeding
- Migrate a server that actually runs a workload (IIS or SQL Server) and test the app after cutover
- Use **dependency analysis** to discover what talks to the server before moving it
- Connect AWS and Azure with a site-to-site VPN so replication runs over a private link instead of public IPs
- Migrate a Linux EC2 instance and compare the process
