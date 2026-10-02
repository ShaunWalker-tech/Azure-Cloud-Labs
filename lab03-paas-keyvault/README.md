# Lab 03: Modernizing to PaaS and Securing Secrets

I replaced the hand-managed database VM from Lab 02 with a fully managed **Azure SQL Database**, then solved the problem that creates: how does the web server get the database password without it ever being typed into code? The answer is **Azure Key Vault** plus a **Managed Identity** on the web VM.

| | |
|---|---|
| **Difficulty** | Intermediate |
| **Time** | About 60 minutes |
| **Region** | West US 2 |
| **Concepts** | PaaS, Azure SQL Database, Key Vault, Managed Identity, RBAC, observability |

---

## Objective

Decommission `vm-db-01` from Lab 02, replace it with Azure SQL Database, store the database password in Key Vault instead of anywhere in code, and let the existing web server (`vm-web-01`) retrieve that password automatically using its own Azure identity — no password ever hardcoded or typed into an app.

## Architecture

```mermaid
flowchart LR
    Web["vm-web-01<br/>Managed Identity"] -->|1. fetch secret| KV["Key Vault<br/>kv-lab03-shaun6"]
    Web -->|2. connect| SQL["Azure SQL<br/>sqldb-app"]
    OldDB["vm-db-01<br/>(deleted)"]

    style OldDB stroke-dasharray: 5 5,opacity:0.5
```

## Skills Demonstrated

- Decommissioning IaaS resources as part of a migration (VM + disk + NIC)
- Deploying a managed **PaaS database** (Azure SQL Database, DTU Basic tier)
- Correctly removing the "Free offer" default to unlock the Basic tier
- Deploying and configuring **Azure Key Vault** with RBAC as the permission model
- Granting **least-privilege roles**: Administrator for the person setting it up, Secrets User for the VM
- Enabling a **system-assigned Managed Identity** and using it to authenticate without credentials
- Validating a live resource with **Azure Monitor metrics**
- Reading a resource group's full deletion manifest before confirming clean-up

## Resources Deployed

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-lab03-shaun` | West US 2 |
| SQL Server (working) | `sql-server-shaun5` | Created after the first name attempt below |
| SQL Database | `sqldb-app` | DTU Basic tier, 5 DTUs, 2 GB max size, ~$4.90/month |
| Key Vault | `kv-lab03-shaun6` | Standard tier, RBAC permission model |
| Secret | `SqlAdminPassword` | The SQL admin password, stored once |
| Existing web VM (from Lab 02) | `vm-web-01` in `rg-lab02-shaun` | Given a system-assigned Managed Identity |

---

## Walkthrough

### Phase 1: Resource group

Created `rg-lab03-shaun` in **West US 2** (the lab guide suggested East US, but any region works).

![Resource groups before Lab 03](./docs/screenshots/01-resource-groups-list.png)
![Create resource group form](./docs/screenshots/02-create-resource-group.png)

### Phase 2: Deploy Azure SQL Database

Started from **SQL databases → Create → SQL database** (not the Free offer).

![SQL databases empty, create dropdown open](./docs/screenshots/03-sql-databases-create-dropdown.png)

My first attempt at naming the server was `sql-server-shaun`:

![Create SQL Database Server panel](./docs/screenshots/04-create-sql-server-panel.png)
![Authentication set to SQL authentication](./docs/screenshots/05-sql-auth-sqladmin.png)

Configured the compute tier to DTU-based, Basic, 5 DTUs:

![Configure DTU Basic tier](./docs/screenshots/06-configure-dtu-basic.png)
![Backup storage redundancy set to LRS](./docs/screenshots/07-backup-redundancy-lrs.png)

Set networking to a public endpoint with both firewall toggles enabled, so the web VM and I could both reach it:

![Networking public endpoint, both toggles Yes](./docs/screenshots/08-networking-public-endpoint.png)
![SQL deployment complete](./docs/screenshots/09-sql-deployment-complete.png)

### Phase 3: Deploy Key Vault

![Key vaults empty](./docs/screenshots/10-key-vaults-empty.png)

My first attempt at a Key Vault name was taken, so I landed on `kv-lab03-shaun6`:

![Review and create showing kv-lab03-shaun6](./docs/screenshots/11-create-keyvault-review.png)
![Key Vault deployment succeeded](./docs/screenshots/12-keyvault-deployment-succeeded.png)

**Granting myself access immediately after creation** — with RBAC as the permission model, nobody has access by default, including the creator:

![Key Vault Access control IAM landing page](./docs/screenshots/13-keyvault-iam.png)
![Add role assignment, Key Vault Administrator in the roles list](./docs/screenshots/14-add-role-assignment-roles-list.png)
![Selecting my own account as the member](./docs/screenshots/15-select-members-admin.png)

### Phase 4: Store the SQL password as a secret

![Secrets list empty](./docs/screenshots/16-secrets-empty.png)
![Create a secret named SqlAdminPassword](./docs/screenshots/17-create-secret-sqladminpassword.png)

### Phase 5: Managed Identity + Key Vault access

**Part A — enable the identity on the web VM:**

![vm-web-01 system-assigned identity enabled](./docs/screenshots/18-vm-web-identity-enabled.png)

**Part B — grant that identity read access to the vault:**

![Back on the Key Vault IAM page to add the second role](./docs/screenshots/19-keyvault-iam-return.png)
![Role list filtered to Key Vault Secrets User](./docs/screenshots/20-add-role-assignment-roles-filtered.png)
![Selecting vm-web-01 as the managed identity](./docs/screenshots/21-select-managed-identity-vm-web.png)
![Confirmation toast: vm-web-01 added as Key Vault Secrets User](./docs/screenshots/22-role-assignment-added-toast.png)

### Phase 6: Validate with Azure Monitor

![DTU percentage metrics chart for sqldb-app](./docs/screenshots/23-dtu-metrics-chart.png)

The chart confirms the database is live and being measured, which is the point of this step — not the specific percentage.

### Clean-up

![Delete resource group showing all 6 dependent resources](./docs/screenshots/24-delete-resource-group.png)

---

## ⚠️ A Mistake I'm Documenting Honestly

Look closely at the clean-up screenshot: the resource group had **two SQL servers** (`sql-server-shaun` and `sql-server-shaun5`) and **two empty `master` databases**, one under each server. Only `sql-server-shaun5` actually hosts `sqldb-app`.

**What happened:** my first server name, `sql-server-shaun`, went through far enough to create the server itself (and its default `master` database) before I restarted the "Create SQL Database" wizard — possibly because I backed out partway through, or the name validated but something else in that first attempt didn't complete cleanly. Either way, I ended up creating a second server, `sql-server-shaun5`, and that's the one that actually finished with `sqldb-app` attached.

**The result:** `sql-server-shaun` sat in the resource group the whole lab as a completely unused, empty server — no database doing any real work, just quietly existing (and technically capable of being billed, though an empty logical server itself has no compute cost; a forgotten database on it would).

**What I'd do differently:** before starting the "Create SQL Database" wizard a second time, check whether a server from an earlier attempt already exists and either reuse it or deliberately delete it first, rather than creating a new one and leaving the old one behind. This is exactly the kind of orphaned resource that's easy to miss if you're not in the habit of reviewing a resource group's full contents before tearing it down — which is also why Phase 6's resource group deletion screen (listing every dependent resource by name) is worth actually reading rather than clicking through.

---

## Notes and Decisions

- **Region:** West US 2, not the East US the lab guide suggested.
- **Naming collisions:** both the SQL Server name and the Key Vault name needed a numeric suffix on a later attempt (`sql-server-shaun5`, `kv-lab03-shaun6`) because the plain name was already in use — a direct consequence of these resource types needing a globally unique public DNS hostname.
- **Key Vault Administrator was granted to my own account**, shown in the portal as a guest-style identity (`...@shaunwalker432gmail.onmicrosoft.com`) — this is normal for a personal Gmail-based Azure trial account appearing inside its own default Microsoft Entra tenant, not a different person's account.
- **Public endpoint on the SQL Server** is intentional, not a security gap — see the concepts notes below for why this doesn't contradict Lab 02's "no public IP" lesson.

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| SQL Database creation fails | Server name already taken | Add a number, e.g. `sql-server-shaun1990` |
| Stuck on Free/Serverless tier after creation | The free offer banner wasn't removed before configuring | Don't try to change the tier after deployment (vCore options can run $400+/month) — just use CPU percentage instead of DTU percentage in Phase 6 |
| "Unauthorized to view contents" in Key Vault | Self-access (Key Vault Administrator) was never granted | Access control (IAM) → Add role assignment → Key Vault Administrator → your own account |
| `vm-web-01` missing from the managed identity picker | Managed Identity wasn't saved, or hasn't propagated yet | Confirm the Object ID is present under the VM's Identity blade; wait 60 seconds and retry |
| An extra, unused SQL Server shows up at clean-up | A previous server-creation attempt completed partially | Check for it before starting a second attempt; delete it explicitly if it's not needed |

## Key Concepts Recap

- **PaaS vs. IaaS:** the same job (hosting a database) done two different ways — a VM you patch and back up yourself, versus a managed service you just use.
- **DTU (Database Transaction Unit):** a bundled measure of CPU, memory, and I/O. Basic tier = 5 DTUs, plenty for a lab.
- **RBAC on Key Vault:** permissions are assigned as roles on identities, not configured directly on the vault — the same model used in Azure governance generally.
- **Identity and access are separate from existence:** creating the Key Vault doesn't grant access to it, even for the creator. Needing access doesn't require a password — Managed Identity proves the VM's identity directly to Azure AD.
- **Why the SQL Database is public but still secure:** Lab 02 removed the public IP entirely so there was no route in at all. Here, the database is reachable by design, but protected by firewall rules (only Azure services and one specific IP) plus the requirement for valid SQL credentials. Different services call for different controls — the goal is always "only the right things can get in," not "nothing can ever be public."

## What I Learned

- Deleting a VM to migrate to PaaS means deleting three things, not one: the VM, its disk, and its NIC — a stopped VM alone still costs money.
- Globally unique naming requirements (SQL Server, Key Vault) make naming collisions a normal, expected part of working in a shared-namespace cloud, not a sign something's wrong.
- RBAC's "no access by default, even for the owner" behavior is a deliberate security posture, not a bug — and it's one of the clearest demonstrations of least privilege in Azure.
- A Managed Identity removes an entire category of secret-management problems (no password to create, rotate, or leak) by letting Azure itself vouch for a resource's identity.
- Reviewing a resource group's full dependent-resource list before deleting it is also how you catch your own leftover mistakes, like the orphaned SQL Server here.

## Possible Next Steps

- Delete the orphaned `sql-server-shaun` explicitly as its own clean-up step before tearing down the whole resource group, to practice the habit of catching this kind of leftover resource
- Actually connect to `sqldb-app` from `vm-web-01` using the retrieved secret, rather than just proving the retrieval pattern
- Add an alert rule on DTU percentage instead of just eyeballing the metrics chart
- Rebuild this same Key Vault + Managed Identity pattern with Terraform
