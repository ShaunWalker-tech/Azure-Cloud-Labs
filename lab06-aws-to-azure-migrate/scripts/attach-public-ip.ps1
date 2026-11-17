<#
.SYNOPSIS
  After cutover: give the migrated VM a public IP and the RDP NSG so you can log in
  and prove it's the same server (hostname should match the EC2 hostname).
#>
param([string]$ResourceGroup = "rg-migrate-target-yourname",
      [string]$Nsg = "nsg-migrate-target-yourname")

$nic = az network nic list -g $ResourceGroup --query "[0].name" -o tsv
$cfg = az network nic ip-config list -g $ResourceGroup --nic-name $nic --query "[0].name" -o tsv

az network public-ip create -g $ResourceGroup --name pip-migrated-vm --sku Standard
az network nic ip-config update -g $ResourceGroup --nic-name $nic --name $cfg --public-ip-address pip-migrated-vm
az network nic update -g $ResourceGroup --name $nic --network-security-group $Nsg

$ip = az network public-ip show -g $ResourceGroup --name pip-migrated-vm --query ipAddress -o tsv
Write-Host "RDP to $ip as Administrator (same password as the EC2 server)."
Write-Host "Then run: hostname ; winver"
