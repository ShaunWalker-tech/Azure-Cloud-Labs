<#
.SYNOPSIS
  Run on the EC2 source server (RDP in, PowerShell as Administrator).
  Opens WinRM so the Azure Migrate appliances can log in and inventory the server.
#>

Enable-PSRemoting -Force -SkipNetworkProfileCheck

# WinRM's default firewall rule only allows the local subnet. Allow remote callers;
# the AWS security group still limits port 5985 to the appliance IP (/32).
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -RemoteAddress Any

Get-Service WinRM
hostname   # this is the name the server shows up under in Azure Migrate

# If validation from the appliance still says "Access is denied":
# local admin accounts are filtered for remote logins by default. Lab-only fix:
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
#   -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord
# Restart-Service WinRM
