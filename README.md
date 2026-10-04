# Azure Cloud Labs

Hands-on Azure labs I completed while building my cloud engineering skills. Every lab folder contains a full write-up, screenshots from my own deployment, and honest notes about what went right and what I'd fix.

## Labs

| # | Lab | What I built | Key skills |
|---|-----|--------------|-----------|
| 01 | [Static website on Blob Storage](./lab01-static-website) | A public website hosted with no server | Resource groups, storage accounts, static hosting, PaaS / serverless |
| 02 | [Secure 2-tier web application](./lab02-secure-2tier-app) | A public web tier and a private database tier on one VNet | Virtual networks, subnetting, NSGs, jump-host SSH access |
| 03 | [Modernizing to PaaS and securing secrets](./lab03-paas-keyvault) | Replaced a VM database with Azure SQL, secured its password with Key Vault and Managed Identity | Azure SQL Database, Key Vault, RBAC, Managed Identity, observability |
| 04 | [Infrastructure as Code with Terraform](./lab04-terraform-iac) | A resource group, VNet, subnet, and NSG deployed, changed, and destroyed entirely from code | Terraform, IaC, state management, init / plan / apply / destroy |

More labs will be added as I complete them.

## How each lab is organized

```
labNN-topic/
├── README.md          Write-up: objective, architecture, steps, screenshots, lessons
├── terraform/         Terraform config, for IaC labs (state files are git-ignored)
└── docs/
    └── screenshots/   Numbered screenshots from my own deployment
```

## About

**Shaun Walker** | [GitHub](https://github.com/ShaunWalker-tech) | [LinkedIn](https://www.linkedin.com/in/shaun-walker-667855349)
