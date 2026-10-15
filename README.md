Zomato Clone: End-to-End DevSecOps CI/CD on Microsoft Azure

A React Zomato clone, shipped through a complete CI/CD pipeline on Azure: Azure DevOps → SonarQube → ACR Tasks → Trivy → Azure Container Registry → Argo CD (GitOps) → AKS.

Every push to master is tested, checked for code quality, built into a container image and scanned for vulnerabilities. Argo CD keeps the AKS cluster in sync with the Kubernetes manifests in this repo.

Tech stack
Area	Tool
Source control & CI	Azure Repos, Azure Pipelines
Code quality	SonarQube Community Build (on AKS, installed with Helm)
Image build	Docker, ACR Tasks (az acr build)
Image security	Trivy (HIGH / CRITICAL scan)
Registry	Azure Container Registry
Continuous deployment	Argo CD (GitOps)
Runtime	Azure Kubernetes Service, 2 × Standard_D2ps_v6 (ARM64) nodes
Exposure	Kubernetes LoadBalancer service (port 80 → 3000)
App	React (Create React App), Node.js 20
Pipeline stages (azure-pipelines.yml)
Prepare SonarQube analysis
Install Node.js and npm dependencies
Run unit tests
Run SonarQube analysis and publish the quality gate
Build the image in Azure with az acr build and push it to ACR (tags: build ID and latest)
Scan the image with Trivy
Repository layout
├── src/, public/          React application
├── Dockerfile             Multi-stage build (Node 20, extended npm timeouts)
├── azure-pipelines.yml    CI pipeline
├── manifests/
│   ├── Deployment.yml     2 replicas of the app image from ACR
│   └── svc.yml            LoadBalancer service, port 80 → 3000
└── docs/
    └── architecture.png
How to reproduce

1. Azure resources

powershell
az group create --name rg-zomato --location canadacentral
az provider register --namespace Microsoft.ContainerRegistry
az acr create --resource-group rg-zomato --name <acr-name> --sku Basic
az aks create --resource-group rg-zomato --name aks-zomato --node-count 2 `
  --node-vm-size Standard_D2ps_v6 --generate-ssh-keys --attach-acr <acr-name>
az aks get-credentials --resource-group rg-zomato --name aks-zomato

2. SonarQube on AKS

powershell
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm install sonarqube sonarqube/sonarqube -n sonarqube --create-namespace `
  --set community.enabled=true --set monitoringPasscode=<passcode>

3. Azure DevOps: create the service connections that azure-pipelines.yml uses: SonarQube (SonarQube Server) and azure-connection (Azure Resource Manager).

4. Argo CD: connect this repository, then create an application with path manifests, revision master, destination https://kubernetes.default.svc, namespace default.

5. Build the image for ARM64 nodes

powershell
az acr build --registry <acr-name> --image zomato:latest --platform linux/arm64 .
kubectl rollout restart deployment zomato
kubectl get svc zomato-service   # open http://<EXTERNAL-IP>
Problems solved along the way
Problem	Fix
Standard_D2s_v3 not allowed in the region	Used ARM64 Standard_D2ps_v6 nodes
Docker Hub 401 when building on the hosted agent	Moved the build to ACR Tasks (az acr build)
Pods in CrashLoopBackOff: exec format error	Image was amd64 on ARM64 nodes; rebuilt with --platform linux/arm64
npm ERR_SOCKET_TIMEOUT during the ARM64 build	Node 20 and longer npm fetch timeouts and retries in the Dockerfile
Argo CD repo connection returned 302	Authenticated with an Azure DevOps Personal Access Token
Argo CD app path does not exist	Set the application path to manifests
Results
Pipeline green on master; SonarQube quality gate Passed
Argo CD application Healthy and Synced
2 replicas running on AKS behind an Azure Load Balancer
Next steps
Add --platform linux/arm64 to the pipeline build step
Fail the pipeline on CRITICAL Trivy findings
Enable Argo CD auto-sync with self-heal and automatic image-tag updates
Add unit tests and monitoring (Prometheus + Grafana)
Credits

The React application is based on the open-source Zomato clone used in the DevOps course (devopsbyraham/Zomato-Project). The Azure infrastructure, pipeline, GitOps setup and fixes are by Jeet Patel.