# Post-Deployment Report - Azure Firewall Explicit Proxy Lab

| | |
|---|---|
| **Date** | 2026-06-17 |
| **Subscription** | `<your-subscription-id>` |
| **Resource group** | `rg-fwproxy-lab` |
| **Region** | East US 2 |
| **Deploy mode** | Local apply (`az deployment group create`) |
| **IaC** | Bicep (`infra/fwlab.bicep`), API `2024-07-01` |
| **Status** | ✅ Succeeded & verified |

## 1. Resource inventory

| Resource | Type |
|---|---|
| `vnet-fwlab` | `Microsoft.Network/virtualNetworks` |
| `fwpol-fwlab` | `Microsoft.Network/firewallPolicies` (explicit proxy ON) |
| `afw-fwlab` | `Microsoft.Network/azureFirewalls` (Standard) |
| `pip-afw-fwlab` | `Microsoft.Network/publicIPAddresses` |
| `pip-bastion-fwlab` | `Microsoft.Network/publicIPAddresses` |
| `bastion-fwlab` | `Microsoft.Network/bastionHosts` (Basic) |
| `nic-client-fwlab` | `Microsoft.Network/networkInterfaces` |
| `vm-client-fwlab` | `Microsoft.Compute/virtualMachines` (Ubuntu 22.04, B2s) |
| `vm-client-fwlab_OsDisk_…` | `Microsoft.Compute/disks` (StandardSSD_LRS) |
| `vm-client-fwlab/MDE.Linux` | `…/virtualMachines/extensions` (Defender for Endpoint, auto-onboarded via policy) |

**Firewall proxy endpoint:** `10.0.0.4` - HTTP `8080`, HTTPS `8443`. **Egress public IP:** `52.251.94.135`.

## 2. Verification results

Run from `vm-client-fwlab` via `az vm run-command`:

| Test | Result | Verdict |
|---|---|---|
| HTTP proxy `:8080` → `ifconfig.me` (allowed) | returned `52.251.94.135` (firewall public IP) | ✅ egress via firewall confirmed |
| HTTPS proxy `:8443` → `www.microsoft.com` (allowed) | `HTTP 200` | ✅ allowed |
| HTTPS proxy `:8443` → `www.google.com` (not allowed) | `curl (56) HTTP code 470 from proxy after CONNECT` | ✅ **denied by app rule** |
| Direct (no proxy) → internet | `HTTP 200` | ⚠️ default outbound still open (see §4) |

The explicit proxy works and the application-rule allowlist is enforced.

## 3. Cost estimate

List price, East US 2, pay-as-you-go (excludes data processing / egress):

| Resource | Rate | ~Monthly |
|---|---|---|
| Azure Firewall (Standard) - deployment | $1.25/hr | ~$913 |
| Azure Firewall - data processing | $0.016/GB | usage-based |
| Bastion (Basic) | $0.19/hr | ~$139 |
| VM `Standard_B2s` (Linux) | $0.0416/hr | ~$30 |
| OS disk (StandardSSD) | - | ~$2.40 |
| Public IP (Standard) × 2 | $0.005/hr ea | ~$7.30 |
| **Total** | | **~$1,090/mo** |

> This is a tear-down-after lab. Run `scripts/teardown.ps1` when done. Hourly burn ≈ **$1.49/hr**.

## 4. Security / WAF posture

Findings specific to this **lab** build (intentionally minimal):

| # | Finding | Recommendation |
|---|---|---|
| 1 | **Client not configured for the proxy** - the VM uses default outbound internet directly; nothing routes to `:8080`/`:8443` until the client is pointed at the proxy (env vars / PAC / app config) | First configure the client (`http_proxy`/`https_proxy` or a hosted PAC file). THEN, as defense-in-depth, deny direct egress with an NSG on `snet-workload` (`Internet:80,443`) or a default-outbound-disabled subnet. Order matters - an NSG alone doesn't redirect traffic to the proxy, it only blocks the bypass |
| 2 | **No TLS inspection** - Standard tier CONNECT-tunnels HTTPS without inspecting payload | Move to **Firewall Premium** + CA cert in policy if you need TLS inspection / IDPS on proxied traffic |
| 3 | **VM uses password auth** | Prefer SSH key auth; the lab password is stored locally only and is **excluded from the repo** |
| 4 | **No NSG on workload subnet** | Add a least-privilege NSG even in lab to model production posture |
| 5 | Threat Intel mode = default (Alert) on Standard | Set to `Deny` to block known-malicious FQDNs/IPs |

✅ Positives: private-only client VM (no public IP), Bastion for management, Defender for Endpoint auto-onboarded, secrets kept out of source control.

> For a formal Well-Architected scan, run `azqr scan -s <your-subscription-id> -g rg-fwproxy-lab`.

## 5. Next steps

- [ ] Configure the client to use the proxy (env vars / PAC), verify, THEN add the bypass-blocking NSG (finding #1)
- [ ] Trial PAC-file hosting (`enablePacFile: true` + SAS URL + `pacFilePort`)
- [ ] Promote to Premium to test TLS inspection of proxied HTTPS
- [ ] Promote to the GitOps pipeline (Deliver mode) for repeatable, approval-gated deploys
