# Zomato on Azure — IaC, GitOps & Monitoring (AKS)

Deploy a React **Zomato clone** to **Azure Kubernetes Service**, built entirely from code:

> **Terraform → AKS (ARM64) → Azure Container Registry → Argo CD (GitOps) → Prometheus / Grafana**

Everything the cluster runs comes from this repository. Terraform builds the infrastructure, the container image is built in the cloud with ACR Tasks (no local Docker required), Argo CD keeps the cluster continuously in sync with the `manifests/` folder, and Prometheus + Grafana — both in-cluster and via Azure Managed Prometheus — provide monitoring.

Built and documented on a **Windows + PowerShell** workstation.

---

## Architecture

```
                 terraform apply
 Developer ───────────────────────────►  Azure Resource Group (Zomato_project)
                                          ├── AKS cluster (2 × Standard_D2ps_v6, ARM64)
                                          └── Azure Container Registry (Basic)  ◄── az acr build (linux/arm64)
                                                                                     builds & pushes the app image

 GitHub repo (this repo) ──watched by──►  Argo CD (in-cluster)
   manifests/Deployment.yml                 │ applies on sync
   manifests/svc.yml                        ▼
                                          AKS: 2 app pods + LoadBalancer Service ──► Public IP (port 80 → 3000)

 Monitoring:
   kube-prometheus-stack (Helm)  ──►  in-cluster Prometheus + Grafana (port-forward)
   az aks ... --enable-azure-monitor-metrics  ──►  Azure Managed Prometheus ──► "Dashboards with Grafana" in the Azure portal
```

**Key idea (GitOps):** you never `kubectl apply` by hand. You change a file in `manifests/`, push to GitHub, and Argo CD makes the cluster match. Git is the single source of truth.

---

## Tech stack

| Area | Tool |
|---|---|
| Infrastructure as Code | Terraform (azurerm provider) |
| Kubernetes | Azure Kubernetes Service (AKS), Free tier control plane |
| Nodes | 2 × `Standard_D2ps_v6` (ARM64 / Ampere, 2 vCPU · 8 GB) |
| Image registry | Azure Container Registry (Basic) |
| Image build | ACR Tasks — `az acr build` (cloud build, no local Docker) |
| Continuous deployment | Argo CD (GitOps) |
| App exposure | Kubernetes `LoadBalancer` Service → Azure public IP (port 80 → 3000) |
| Monitoring (in-cluster) | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) via Helm |
| Monitoring (portal) | Azure Monitor Managed Prometheus + Dashboards with Grafana |
| App | React (Create React App), Node.js 20 |

---

## Repository layout

```
terraform/            # IaC: resource group, AKS cluster, ACR, AcrPull role assignment
  providers.tf        #   azurerm provider (~> 4.0)
  variables.tf        #   inputs (subscription_id, region, node size, acr_name, ...)
  main.tf             #   resource group + AKS cluster
  acr.tf              #   ACR + role assignment (cluster can pull images)
  outputs.tf          #   cluster name, get-credentials command
  terraform.tfvars    #   YOUR values (gitignored — never committed)
manifests/            # Argo CD source of truth
  Deployment.yml      #   2 replicas, image from ACR, resource limits
  svc.yml             #   LoadBalancer, port 80 → 3000
src/, public/         # React application
Dockerfile            # Multi-stage Node 20 build
azure-pipelines.yml   # (optional) Azure DevOps CI — not required for the GitOps flow below
```

---

## Prerequisites (Windows)

Install with `winget`, then restart your terminal:

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.AzureCLI -e
winget install --id Hashicorp.Terraform -e
winget install --id Kubernetes.kubectl -e
winget install --id Helm.Helm -e
```

Sign in and select your subscription:

```powershell
az login
az account show -o table
az account set --subscription "<your-subscription>"   # if you have more than one
```

Register the resource providers used here (one-time per subscription):

```powershell
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Monitor
```

> **Tip:** keep this repo on a **non-OneDrive** drive. OneDrive sync corrupts Terraform's state and plugin files mid-run.

---

## Reproduce it

### 1. Provision the infrastructure (Terraform)

Create `terraform/terraform.tfvars` (gitignored) with your values:

```hcl
subscription_id = "<your-subscription-id>"   # az account show --query id -o tsv
location        = "canadacentral"
acr_name        = "<globally-unique-acr-name>"
node_vm_size    = "Standard_D2ps_v6"         # see "Gotchas" about VM sizes
```

Then:

```powershell
cd terraform
terraform init
terraform validate
terraform plan        # expect: Plan: 4 to add (RG, AKS, ACR, role assignment)
terraform apply       # type "yes"; ~5-10 min

# connect kubectl to the new cluster
az aks get-credentials --resource-group Zomato_project --name Zomato --admin --overwrite-existing
kubectl get nodes     # 2 nodes, STATUS Ready
```

### 2. Build & push the app image (ACR Tasks)

Built in the cloud — **no Docker Desktop needed**. `--platform linux/arm64` is required because the nodes are ARM64.

```powershell
cd ..                 # repo root (where the Dockerfile is)
az acr build --registry <acr-name> --image zomato:latest --platform linux/arm64 .
az acr repository show-tags --name <acr-name> --repository zomato -o table   # expect: latest
```

Point `manifests/Deployment.yml` at your registry (`image: <acr-name>.azurecr.io/zomato:latest`) and push to GitHub so Argo CD sees it.

### 3. Deploy with Argo CD (GitOps)

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd            # wait until all Running

# expose Argo CD on a public IP (patch via file to avoid PowerShell quoting issues)
'{"spec":{"type":"LoadBalancer"}}' | Set-Content patch.json
kubectl patch svc argocd-server -n argocd --patch-file patch.json
Remove-Item patch.json
kubectl get svc argocd-server -n argocd   # wait for EXTERNAL-IP

# admin password (Windows base64 decode)
$enc = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($enc))
```

Open `http://<argocd-external-ip>`, log in as `admin`, then **New App**:

| Field | Value |
|---|---|
| Application Name | `zomato` |
| Project | `default` |
| Sync Policy | `Manual` |
| Repository URL | this repo's `.git` URL |
| Revision | `HEAD` |
| Path | `manifests` |
| Cluster URL | `https://kubernetes.default.svc` |
| Namespace | `default` |

Click **Create → Sync → Synchronize**, then:

```powershell
kubectl get pods       # app pods Running
kubectl get svc        # zomato-service EXTERNAL-IP
```

Open `http://<zomato-service-external-ip>` — the Zomato app is live.

### 4. Monitoring

```powershell
# in-cluster Prometheus + Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
kubectl get pods -n monitoring        # wait until all Running

# reach Grafana locally (no public IP) — run in its own terminal; it stays open
kubectl port-forward svc/prometheus-grafana -n monitoring 3001:80
# Grafana: http://localhost:3001  (user: admin)
$enc = kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($enc))

# Azure Managed Prometheus (metrics in the Azure portal)
az aks update --resource-group Zomato_project --name Zomato --enable-azure-monitor-metrics
# Portal: AKS cluster → Monitoring → Dashboards with Grafana → "Kubernetes | Compute Resources | Cluster"
```

---

## Gotchas & lessons learned

These are the real walls hit during this build — documented so the next person (or the next me) doesn't re-derive them.

1. **Subscription VM-size allow-list.** A new pay-as-you-go subscription can *block* common sizes (e.g. `Standard_B2s`) regardless of region availability. The create error returns the exact list of *allowed* sizes — read it. `az vm list-skus` does **not** reveal this; it only shows region availability.

2. **Two independent quota layers.** A VM size must clear **both** the "Total Regional vCPUs" quota **and** a separate **per-VM-family** quota. We had 10 regional vCPUs but `0` for the `Bpsv2` family. Check per-family with:
   ```powershell
   az vm list-usage --location canadacentral -o table | Select-String "Family vCPUs|Regional"
   ```
   We landed on the `Dpsv6` family (`Standard_D2ps_v6`), which had quota.

3. **ARM64 nodes need ARM64 images.** `Standard_D2ps_v6` is Ampere/ARM64. An `amd64` image on ARM nodes = `CrashLoopBackOff` with `exec format error`. Fix: `az acr build ... --platform linux/arm64`.

4. **The React dev server is memory-hungry.** The Dockerfile runs `npm start` (CRA dev server), which steady-states near ~390 MiB/pod and spikes higher while compiling on boot — `OOMKilled` (exit 137) under a `512Mi` limit. Fix applied: raise the limit to `1Gi`. **Proper fix (future work):** build the static bundle and serve it with nginx (~10–20 MB).

5. **Grafana via port-forward, not a public IP.** Grafana only needs the admin, so tunnel `localhost:3001` to the pod instead of paying for and exposing a third public IP.

6. **Resources created outside Terraform aren't destroyed by Terraform.** `--enable-azure-monitor-metrics` (and any Azure Managed Grafana) are created via the CLI/portal, so `terraform destroy` leaves them behind. Delete them manually (see Cleanup).

7. **Windows/PowerShell specifics.** Quote paths with spaces; `kubectl patch` inline JSON gets mangled by PowerShell — use `--patch-file`; decode Kubernetes secrets with .NET (`[Convert]::FromBase64String`), not the Linux `base64 -d`.

---

## Cleanup (stop the billing)

Everything here bills by the hour (2 nodes, 2 public IPs, load balancer, ACR, managed monitoring). Tear down when done:

```powershell
cd terraform
terraform destroy      # removes RG, AKS, ACR, role assignment

# delete what Terraform did NOT create:
az group list -o table
az group delete --name "<DefaultAzureMonitorWorkspace resource group>" --yes --no-wait
# and delete the Azure Managed Grafana instance if you created one
```

---

## Future work

- Serve the static build with **nginx** instead of the dev server (smaller, safer, no OOM).
- Add **CI** (GitHub Actions or the included Azure DevOps pipeline) to build the image and bump the manifest tag automatically.
- Move Terraform **state to an Azure Storage** backend for team sharing and locking.
- Enable Argo CD **auto-sync + self-heal**.
- Add Alertmanager rules → Slack/email notifications.

---

## Credits

The React Zomato clone is based on the open-source course app (`devopsbyraham/Zomato-Project`). The Azure infrastructure, GitOps setup, monitoring, and the fixes documented above are by **Jeet Patel**.