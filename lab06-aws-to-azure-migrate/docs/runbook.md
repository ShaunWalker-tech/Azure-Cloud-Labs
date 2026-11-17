# Runbook

The condensed, working version of the lab: every step that's here worked, and every fix from [troubleshooting.md](troubleshooting.md) is already applied. Run the commands in PowerShell on your own PC unless a step says otherwise.

## Phase 0: Local setup

1. **Use a dedicated IAM user for Terraform.** Code-only, no console access. Give it `AmazonEC2FullAccess`, `AmazonVPCFullAccess`, and `IAMFullAccess`. Never hand the root user's keys to a tool.
2. **Install the tools:** `winget install HashiCorp.Terraform Amazon.AWSCLI Microsoft.AzureCLI`
3. **Sign in to both clouds:** `aws configure` (region `us-east-1`), then `az login` and `az account set --subscription "<name>"`.
4. **Run the pre-flight checks:** `.\scripts\preflight-checks.ps1 -Location centralus`. Request quota *now* (Total Regional vCPUs and Standard Dasv7 Family vCPUs → 20) if it's short.

## Phase 1: AWS source server (`terraform/aws-side/`)

1. **Get a current Windows Server 2022 AMI:**
   ```powershell
   aws ec2 describe-images --region us-east-1 --owners amazon `
     --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" "Name=state,Values=available" `
     --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
   ```
2. **Configure and build:** copy `terraform.tfvars.example` → `terraform.tfvars` and fill it in. Then run `terraform init`, `terraform plan`, `terraform apply`. Expect **14 added**.
3. **Prepare the server:** RDP in as `Administrator` and run [`scripts/enable-winrm-on-ec2.ps1`](../scripts/enable-winrm-on-ec2.ps1). Write down the `hostname` (`EC2AMAZ-…`).

## Phase 2: Azure target (`terraform/azure-side/`)

1. **Configure and build:** copy `terraform.tfvars.example` → `terraform.tfvars` and fill it in. Set `deploy_discovery_appliance = true` and `deploy_replication_appliance = false`, then `terraform init` and `terraform apply`.
2. **Create the Azure Migrate project in the portal.** Terraform can't do this step. Use the source resource group, Geography: United States.

## Phase 3: Discover

1. **Generate the project key:** Azure Migrate → Discover → Using appliance → **Physical or other (AWS, GCP, Xen)**.
2. **Open WinRM to the appliance:** add the `appliance_public_ip` output to `aws-side` `winrm_allowed_cidrs` as a `/32`, then apply. Expect **1 to change**.
3. **Install the appliance:** RDP to the appliance as `.\migrateadmin`, download the installer there, and run `AzureMigrateInstaller.ps1` with scenario 3 (Physical), Azure Public, public endpoint. When it asks to remove Internet Explorer, press **N**.
4. **Register the appliance:** open the Configuration Manager at `https://appl-<name>:44368` and register with the project key.
   - Sign in with a **directory account**, not a personal Microsoft account.
   - Turn Security Defaults **off only while registering**, then turn it back on.
5. **Start discovery:** add a Windows credential (`Administrator`), then add the EC2 **public** IP as the discovery source and click **Start discovery**.

## Phase 4: Assess

1. **Create the assessment:** Azure VM, Central US, Performance-based sizing, pay-as-you-go.
2. **Check the result.** Mine came back: **Ready: 1**, estimated **$40.86 / month** (compute $23.58, storage $2.40, security $14.88).

## Phase 5: Replicate

1. **Swap the appliances:** in `azure-side` set `deploy_discovery_appliance = false`, `deploy_replication_appliance = true`, and `ec2_public_ip = "<EC2 IP>"`, then apply. Point `aws-side` `winrm_allowed_cidrs` at the replication appliance IP and apply.
2. **Install the replication appliance:** RDP in, then Azure Migrate → Migration tools → Discover → Physical or other → **Create resources**. Download the installer and the vault key, then run `DRInstaller.ps1`.
3. **Configure the appliance** at `https://repl-<name>:44368`:
   - **Connectivity:** choose **NAT IP**.
   - **Vault:** register with the key file.
   - **Physical server details:** add the EC2 credential and IP (status **Success**).
   - **Don't click Reset appliance.**
4. **Finalize registration** from the classic Azure Migrate view.
5. **Install the Mobility agent by hand** on EC2 with [`scripts/install-mobility-agent.ps1`](../scripts/install-mobility-agent.ps1).
6. **Start replication:** Replicate → guest credentials `credentialLessRunAsAccount` → target RG, VNet, and subnet → `Standard_E2bds_v5` → **Replicate**.
7. **Wait for it:** Replications should show **Protected / Healthy**.

## Phase 6: Test, then cut over

1. **Test migration** into the target VNet. Confirm the `-test` VM boots: Boot diagnostics should show the lock screen. Then **Clean up test migration**.
2. **Migrate.** In production, shut the source down first to avoid split-brain.
3. **Verify the move:** run [`scripts/attach-public-ip.ps1`](../scripts/attach-public-ip.ps1), RDP in, and run `hostname` and `winver`. The hostname matches the EC2 server.

## Clean-up (same day)

1. **Stop replication.**
2. **Tear everything down:** run [`scripts/teardown.ps1`](../scripts/teardown.ps1).
3. **Retire credentials:** delete the AWS access key and the temporary Entra ID admin, and confirm Security Defaults is back **on**.
