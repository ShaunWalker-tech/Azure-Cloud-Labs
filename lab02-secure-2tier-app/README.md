# Lab 02: Building a Secure 2-Tier Web Application

I built a classic IaaS network architecture on Azure: a Virtual Network split into a **public subnet** (web server) and a **private subnet** (database server), with the database reachable only from inside the network, never from the internet.

| | |
|---|---|
| **Difficulty** | Beginner |
| **Time** | About 60 minutes |
| **Region** | Central US |
| **Concepts** | VNets, subnetting, NSGs, public vs. private IPs, SSH jump access |

---

## Objective

Deploy a two-tier network: a public subnet holding a web server, and a private subnet holding a database server with no public IP. Use a Network Security Group (NSG) to explicitly control what can reach the database, and prove the setup works by connecting through the web server as a jump point.

## Architecture

```mermaid
flowchart TB
    Internet((Internet)) -->|HTTP 80, SSH 22| WebVM[vm-web-01<br/>Public Subnet: snet-web<br/>10.0.1.0/24]
    WebVM -->|ping / SSH jump| DbVM[vm-db-01<br/>Private Subnet: snet-db<br/>10.0.2.0/24<br/>No Public IP]

    subgraph VNet["vnet-lab02 (10.0.0.0/16)"]
        WebVM
        DbVM
    end
```

## Skills Demonstrated

- Designing a **Virtual Network** with multiple subnets
- Separating **public** and **private** tiers by subnet and public IP assignment
- Deploying VMs with **SSH key authentication**
- Using a **jump host** pattern to reach a server with no public IP
- Validating internal connectivity with `ping`
- Writing and testing **Network Security Group (NSG)** rules
- Reading Azure's resource group deletion summary before confirming a tear-down

## Resources Deployed

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-lab02-shaun` | Central US |
| Virtual network | `vnet-lab02` | Address space `10.0.0.0/16` |
| Subnet (public) | `snet-web` | `10.0.1.0/24` |
| Subnet (private) | `snet-db` | `10.0.2.0/24` |
| Web VM | `vm-web-01` | Ubuntu Server 24.04 LTS x64 Gen2, Standard_D4s_v7, Zone 3, Trusted launch, public IP |
| Database VM | `vm-db-01` | Same image/size/zone, **no public IP** |
| SSH key | `key-lab02` | RSA, shared by both VMs |
| NSG rule | `Allow-Web-Subnet` | Allows `10.0.1.0/24` on port 3306 |

> **Note on image and size:** the lab guide suggested Ubuntu 20.04 LTS on a Standard_B1s. I deployed **Ubuntu Server 24.04 LTS (Gen2)** on a **Standard_D4s_v7** instead, in Central US on Availability Zone 3, with Trusted launch enabled as the security type. The core networking and NSG concepts are identical regardless of VM size or image version.

---

## Walkthrough

### Phase 1: The network foundation

**Resource group.** Everything in this lab lives inside one resource group so it can be torn down in a single step.

![Empty resource groups list](./docs/screenshots/01-resource-groups-empty.png)
![Create a resource group form](./docs/screenshots/02-create-resource-group.png)
![Resource group created](./docs/screenshots/03-resource-group-created.png)

**Virtual network.** I created `vnet-lab02` with address space `10.0.0.0/16`, then added two subnets inside it: `snet-web` for anything public-facing, and `snet-db` for anything that should stay internal.

![Create virtual network basics](./docs/screenshots/05-create-vnet-basics.png)
![Add subnet snet-web](./docs/screenshots/06-add-subnet-web.png)
![Add subnet snet-db](./docs/screenshots/07-add-subnet-db.png)
![VNet deployment complete](./docs/screenshots/08-vnet-deployment-complete.png)

### Phase 2: Deploying the web server (public tier)

`vm-web-01` sits in `snet-web`, allows HTTP and SSH inbound, and gets a new public IP.

![Create VM basics for vm-web-01](./docs/screenshots/10-create-vm-web-basics.png)
![VM size and image continued](./docs/screenshots/11-create-vm-web-basics-continued.png)
![SSH key generated for vm-web-01](./docs/screenshots/12-create-vm-web-ssh-key.png)
![Inbound ports HTTP and SSH](./docs/screenshots/13-create-vm-web-inbound-ports.png)
![Networking: snet-web with new public IP](./docs/screenshots/14-create-vm-web-networking.png)

Azure only lets you download the private key once, at creation time:

![Download private key prompt](./docs/screenshots/15-download-private-key.png)
![vm-web-01 deployment complete](./docs/screenshots/16-vm-web-deployment-complete.png)
![vm-web-01 running with public IP](./docs/screenshots/17-vm-web-running.png)

### Phase 3: Deploying the database server (private tier)

This is the step that actually creates the two-tier separation. `vm-db-01` reuses the same SSH key, opens **only SSH** (no HTTP, since it's not a web-facing box), and — critically — sits in `snet-db` with its public IP set to **None**.

![Create VM basics for vm-db-01](./docs/screenshots/18-create-vm-db-basics.png)
![Reusing the existing SSH key for vm-db-01](./docs/screenshots/19-create-vm-db-ssh-key.png)
![Inbound ports: SSH only](./docs/screenshots/20-create-vm-db-inbound-ports.png)
![Networking: snet-db, Public IP set to None](./docs/screenshots/21-create-vm-db-networking.png)
![vm-db-01 deployment complete](./docs/screenshots/22-vm-db-deployment-complete.png)

### Phase 4: Validating connectivity (the "jump")

Because `vm-db-01` has no public IP, my home computer can't reach it directly. I connected to the web server first, then pinged the database server's **private** IP from inside that session.

![vm-web-01 public IP details](./docs/screenshots/23-vm-web-public-ip-details.png)

```bash
cd Downloads
ssh -i key-lab02.pem azureuser@20.118.241.133
```

![Terminal navigating to the downloaded key](./docs/screenshots/24-terminal-navigate-downloads.png)
![SSH connection into vm-web-01](./docs/screenshots/25-ssh-into-web-vm.png)

From inside `vm-web-01`, I pinged the database server's private IP (`10.0.2.4`):

```bash
ping -c 4 10.0.2.4
```

![Successful ping to the database server](./docs/screenshots/26-ping-test-success.png)

Four packets sent, four received, 0% packet loss — confirmation that both VMs can talk to each other inside the VNet, even though the database has no route to or from the public internet.

### Phase 5: Configuring the firewall (NSG)

The last step is adding an explicit rule so that only the web subnet's traffic is allowed through, rather than relying on "no public IP" alone.

![Adding the inbound security rule](./docs/screenshots/27-add-nsg-rule-panel.png)
![Rule added to the NSG](./docs/screenshots/28-nsg-rule-added-list.png)

Rule details: source `10.0.1.0/24` (the web subnet), destination port `3306` (a typical database port), action **Allow**, priority `100`, named `Allow-Web-Subnet`.

### Clean-up

Deleting the resource group removes all 11 dependent resources — both VMs, both NICs, the disk, the SSH key, the NSGs, and the public IP — in one confirmed action.

![Delete resource group confirmation](./docs/screenshots/29-delete-resource-group.png)

---

## ⚠️ A Mistake I'm Documenting Honestly

Looking back at my screenshots, I added the `Allow-Web-Subnet` rule to **`vm-web-01-nsg`** (the web server's NSG), not `vm-db-01-nsg` (the database server's NSG) as the lab intended. You can see the breadcrumb in the screenshots above confirms `vm-web-01-nsg` throughout that step.

**Why this matters:** the point of the exercise was to add a rule to the *database's* NSG restricting inbound traffic to only the web subnet. Adding it to the web server's NSG instead doesn't create any additional protection for the database — `vm-db-01` was already unreachable from the internet simply because it has no public IP, but there was no rule explicitly scoping *internal* VNet access to just the web subnet either.

**What I'd do differently:** go to `vm-db-01`'s Networking tab, open **its** NSG (not the web server's), and add the same rule there. I'm leaving this note in instead of quietly fixing it, because catching and explaining your own mistake is a more honest — and more useful — record than pretending it went perfectly the first time.

---

## Notes and Decisions

- **Region:** Central US, not the East US the lab guide suggested. Any region works for this exercise.
- **VM size and image:** Standard_D4s_v7 on Ubuntu 24.04 LTS (Gen2), not the smaller Standard_B1s on Ubuntu 20.04 the guide listed. This was a larger and more expensive size than necessary for a lab — worth remembering to check the estimated monthly cost panel before deploying next time.
- **Availability Zone 3 + Trusted launch:** both were left at their suggested/default values during creation. Trusted launch adds boot integrity monitoring, which is a reasonable default for any new VM.
- **Why no public IP on the database:** removing the public IP is the first and strongest layer of defense — there's no route in from the internet at all, regardless of any firewall rule. The NSG rule is a second, explicit layer on top of that.

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| Ping to the database fails | `vm-db-01` deployed into the wrong subnet, or the two VMs are in different VNets | Confirm `vm-db-01` is in `snet-db` and both VMs share `vnet-lab02` |
| Can't SSH into `vm-db-01` directly | No public IP by design | SSH into `vm-web-01` first, then reach the database from inside that session |
| NSG rule doesn't seem to do anything | Rule added to the wrong VM's NSG (see the note above) | Add the rule to the *target* VM's own NSG, not the source VM's |

## What I Learned

- Subnetting inside one VNet is how you separate public and private tiers without needing separate networks entirely.
- Removing a public IP is a stronger control than a firewall rule alone — there's no route in from the internet to begin with.
- A jump host (bastion-style access) is the standard way to reach a private server without exposing it directly.
- NSGs are scoped per-resource: a rule only affects the resource whose NSG it's attached to, which means it's easy to attach a rule to the wrong side of a connection, as I did here.
- Reading the resource group's deletion summary before confirming is a good habit — it's the clearest inventory of everything that actually got created during the lab.

## Possible Next Steps

- Fix the NSG placement: add `Allow-Web-Subnet` to `vm-db-01-nsg` instead of `vm-web-01-nsg`
- Install an actual database engine (e.g. MySQL or PostgreSQL) on `vm-db-01` and connect to it from the web server on the real port
- Replace the manual jump-host SSH flow with **Azure Bastion** for browser-based access with no exposed SSH port at all
- Rebuild this same topology with Terraform instead of the portal
