<#
.SYNOPSIS
  Run on the EC2 source server. Installs the Azure Site Recovery Mobility agent by hand.

.WHY
  Push install failed with:
    "Connectivity failure - Mobility service installation failed on the source machine (IP: 10.0.1.78)"
  Push install has to reach the server's PRIVATE IP, and there's no private network
  between AWS and Azure. Installed by hand, the agent connects OUT to the replication
  appliance's public IP over HTTPS (443 / 9443), so no VPN is needed.

.STEPS
  1. Download the installer on the EC2 server: https://aka.ms/latestmobsvc
  2. Run this script.
  3. In the Registration window, copy "Machine Details", paste it into the replication
     appliance's Configuration Manager > Mobility service configuration details, and
     download the configuration file.
  4. Save that file on EC2 as C:\ASR\config.json (git-ignored; never commit it).
  5. Registration window > Browse > C:\ASR\config.json > Register.
#>

New-Item -ItemType Directory -Path C:\ASR -Force | Out-Null
Move-Item "$HOME\Downloads\Microsoft-ASR_UA_*.exe" C:\ASR -ErrorAction SilentlyContinue
Set-Location C:\ASR

$installer = (Get-ChildItem C:\ASR\*.exe | Select-Object -First 1).FullName
& $installer /q /x:C:\ASR\extracted

Set-Location C:\ASR\extracted
.\UnifiedAgentInstaller.exe /Platform vmware /Role MS /CSType CSPrime `
    /InstallLocation "C:\Program Files (x86)\Microsoft Azure Site Recovery"

# Health check once registered. These two should be Running:
#   InMage Scout VX Agent - Sentinel/Outpost, InMage Scout Application Service
Get-Service -DisplayName "*InMage*"
