# red-k3s-image Refactor Plan

## Goal

Refactor `red-k3s-image` into a clean, minimal Packer AMI that produces a
single-node k3s cluster, aligned with `red-mumble-image` conventions. The image
stops at "k3s running and Ready." Everything else (Istio, Gateway API, TLS,
GitOps) is installed after the cluster is up.

## Missions

| Mission                                   | Status                                 |
| ----------------------------------------- | -------------------------------------- |
| Single-node cluster                       | **In scope**                           |
| Public CA (Let's Encrypt for the k8s API) | **Removed from scope** (revisit later) |

---

## Decisions

### Versions

| Component | Version                                                            |
| --------- | ------------------------------------------------------------------ |
| Ubuntu    | 26.04 arm64 (no fallback to 24.04; resolve issues if they come up) |
| k3s       | `v1.37.0+k3s1` (pinned)                                            |
| Helm      | `v4.3.0` (pinned)                                                  |

### Cluster

-   **Datastore:** embedded etcd from day one (`cluster-init: true`)
-   **Role:** one AMI, role selected at boot via `K3S_ROLE`
    -   `server`: implemented
    -   `agent`: fails immediately with a "not yet supported" error
-   **Bundled components:**
    -   Traefik: **disabled**
    -   ServiceLB: enabled (backs Istio's gateway `LoadBalancer` Service on
        80/443)
    -   local-path provisioner: enabled
    -   metrics-server: enabled
-   **Ingress:** Istio implementing the Kubernetes Gateway API, installed after
    the cluster is up
-   **etcd snapshots:** k3s default local snapshots only

### Access

-   **Kubeconfig:** `write-kubeconfig-mode: "0600"`
-   **Access method:** SSM session, switching to root to run `kubectl` and
    `helm`
-   **`DOMAIN`:** required; every cluster gets a Route53 A record. Rendered into
    `tls-san`.
-   **Ports:** handled by the EC2 security group (80, 443, 6443 open)

### OS

-   **Unattended upgrades:** automatic reboot allowed at 07:00 UTC
-   **Timezone:** node stays on UTC
-   **System tuning:** Mumble baseline only, kept simple
-   **Root volume:** 50 GiB default

### First boot

-   Follows the Mumble pattern: cloud-init writes the env file, `runcmd` invokes
    the script
-   The systemd oneshot bootstrap unit is removed
-   The first-boot script is idempotent with a completion sentinel, so it's safe
    to re-run by hand over SSM

---

## First-Boot Env Contract

**Path:** `/etc/red-k3s/first-boot.env`

| Variable   | Required | Values                                                  |
| ---------- | -------- | ------------------------------------------------------- |
| `DOMAIN`   | Yes      | FQDN of the cluster's A record (e.g. `k3s.example.com`) |
| `K3S_ROLE` | Yes      | `server` (`agent` reserved, not yet supported)          |

---

## Change Plan

### Packer files

**`k3s.pkr.hcl`**

-   Switch the source AMI filter to Ubuntu 26.04 arm64, matching Mumble's base
    selection
-   Remove cert-manager references (the tag, environment var, and version)
-   Update the provisioner list to the new script set

**`variables.pkr.hcl`**

-   Remove `cert_manager_version`
-   `k3s_version` default → `v1.37.0+k3s1`
-   `helm_version` default → `v4.3.0`
-   `root_volume_size` default → `50`

**`example.pkrvars.hcl`**

-   Update to match the variables

### Scripts

| Script                    | Change                                                                                                                                                                                    |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `00-wait-cloud-init.sh`   | Port Mumble's version                                                                                                                                                                     |
| `10-apt-baseline.sh`      | Port Mumble's version, including the apt-timer pause. Configure unattended-upgrades with automatic reboot at 07:00 UTC.                                                                   |
| `15-install-ssm-agent.sh` | Port Mumble's version                                                                                                                                                                     |
| `20-system-tuning.sh`     | Port Mumble's baseline                                                                                                                                                                    |
| `30-install-k3s.sh`       | Keep the pinned install that never starts or enables k3s, and keep its bake-time assertions. The server unit is still the only one written; agent unit handling comes with agent support. |
| `35-install-helm.sh`      | **New.** Helm install only, split out of the old script 40.                                                                                                                               |
| `40-stage-assets.sh`      | **Replaces old 40 and 50.** Installs the first-boot script and k3s config template, creates `/etc/red-k3s`, and keeps the `profile.d` `KUBECONFIG` export.                                |
| `99-cleanup.sh`           | Port Mumble's version, including re-enabling the apt timers                                                                                                                               |

**Deleted:** `50-install-bootstrap.sh`

### Files

**Deleted**

-   `files/cert-manager/` (ClusterIssuer and Certificate templates)
-   `files/bin/rotate-k3s-ca`
-   `files/bin/on-cert-renewal`
-   `files/systemd/` (`k3s-bootstrap.service`, `k3s-cert-renewal.service`,
    `k3s-cert-renewal.timer`)

**`files/k3s/config.yaml.tmpl`** renders to:

```yaml
write-kubeconfig-mode: "0600"
tls-san:
    - <DOMAIN>
cluster-init: true
disable:
    - traefik
```

**`files/bootstrap/k3s-bootstrap` → `/usr/local/sbin/red-k3s-first-boot.sh`**
(mirrors Mumble naming)

Flow:

1. Require root; if the sentinel exists, exit 0
2. Source `/etc/red-k3s/first-boot.env` and validate:
    - `DOMAIN` is required
    - `K3S_ROLE=server` continues
    - `K3S_ROLE=agent` exits with "not yet supported"
    - Any other value exits with an error
3. Render `/etc/rancher/k3s/config.yaml` from the template
4. `systemctl enable --now k3s`
5. Wait for `/readyz`, then wait for the node to reach Ready
6. Write the sentinel

Logs to a file as well as the console. Idempotent throughout.

### Repo conventions

-   Port Mumble's `.pre-commit-config.yaml` (`packer fmt` hook)
-   Add Mumble's `.github` issue templates

---

## First Test Build Verification

-   [ ] k3s runs cleanly on Ubuntu 26.04
-   [ ] etcd is the active datastore
-   [ ] Traefik is absent
-   [ ] ServiceLB, local-path, and metrics-server are running
-   [ ] Kubeconfig is `0600`
-   [ ] Re-running the first-boot script after completion is a no-op
-   [ ] `K3S_ROLE=agent` fails with the expected error

---

## Deferred

-   **README rewrite:** first-boot env contract, cloud-init user-data format,
    and a red-instance example mirroring the real cluster
-   **Istio + Gateway API:**
    -   Standard-channel Gateway API CRDs
    -   Istio install (k3s platform settings if using ambient mode)
    -   One shared `Gateway` on a single node, with multiple listeners and
        `allowedRoutes`
    -   `externalTrafficPolicy: Local` on the gateway Service
-   **TLS:** cert-manager with Gateway API support enabled, DNS-01 via Route53
-   **Auth policy:** authenticated by default for anything exposed through the
    Gateway (Istio `RequestAuthentication`, or oauth2-proxy via `ext_authz`)
-   **Agent role support:** `k3s-agent` unit handling and token delivery
-   **Existing cluster migration:** Traefik `Ingress` resources → `HTTPRoute`
    equivalents
-   **Public CA mission**
