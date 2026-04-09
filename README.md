# Simple CI/CD — Jenkins + EKS Pipeline

Deploys a Node.js app to Kubernetes using Jenkins. Everything provisioned by Terraform.

## What Gets Created

- **VPC** — 2 public + 2 private subnets, NAT Gateway, Internet Gateway
- **EKS** — Kubernetes 1.29 cluster with 2× t3.large nodes
- **ECR** — Private Docker registry
- **Jenkins** — Running on EKS (plain K8s manifests, no Helm)
- **App** — Node.js app with LoadBalancer (public access)

## Architecture

```
Developer → Git Push → Jenkins (on EKS)
                          ↓
                    Build Docker Image
                          ↓
                    Push to ECR
                          ↓
                    Deploy to EKS → LoadBalancer → Public
```

## Prerequisites

```bash
# Install these tools
terraform  >= 1.5
aws-cli    >= 2.x
kubectl    >= 1.28
docker     >= 24.x

# Configure AWS
aws configure
aws sts get-caller-identity   # verify
```

## Quick Start (One Command)

```bash
chmod +x deploy.sh destroy.sh
./deploy.sh
```

This runs Terraform, deploys Jenkins, builds the app, pushes to ECR, and deploys to K8s.
Takes ~15-20 minutes (EKS creation is the bottleneck).

## Manual Step-by-Step

### Step 1 — Create Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### Step 2 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name simple-cicd-eks
kubectl get nodes
```

### Step 3 — Deploy Jenkins

```bash
kubectl apply -f jenkins/jenkins-deployment.yaml
kubectl get pods -n jenkins -w          # wait for Running
kubectl get svc jenkins -n jenkins      # get URL
```

Get Jenkins admin password:
```bash
kubectl exec -n jenkins deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

Open `http://<JENKINS_URL>:8080` and complete setup wizard.

### Step 4 — Install Jenkins Plugins

In Jenkins UI → Manage Jenkins → Plugins → Install:
- Pipeline
- Git
- Docker Pipeline
- Kubernetes

### Step 5 — Build & Push App Image

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/simple-cicd-app"

aws ecr get-login-password --region ${REGION} | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

cd app
docker build -t ${ECR_REPO}:1 -t ${ECR_REPO}:latest .
docker push ${ECR_REPO}:1
docker push ${ECR_REPO}:latest
```

### Step 6 — Deploy App to K8s

```bash
sed "s|IMAGE_PLACEHOLDER|${ECR_REPO}:1|g; s|VERSION_PLACEHOLDER|1|g" \
    k8s/app-deployment.yaml | kubectl apply -f -

kubectl get pods -n myapp
kubectl get svc myapp -n myapp     # get public URL
curl http://<APP_URL>
```

### Step 7 — Create Jenkins Pipeline (for future deploys)

1. Jenkins → New Item → Pipeline → name: `myapp`
2. Pipeline → Pipeline script from SCM → Git → your repo URL
3. Script Path: `Jenkinsfile`
4. Edit `Jenkinsfile` — set `AWS_ACCOUNT_ID` to your account ID
5. Build Now

Every subsequent `git push` → Jenkins builds, pushes to ECR, deploys to EKS automatically.

## Verify

```bash
# App
curl http://$(kubectl get svc myapp -n myapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health
curl http://$(kubectl get svc myapp -n myapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health
```

## Cleanup

```bash
./destroy.sh
```

## Files

```
simple-cicd/
├── terraform/main.tf              # All infra (VPC, EKS, ECR, IAM)
├── jenkins/jenkins-deployment.yaml # Jenkins on K8s (no Helm)
├── k8s/app-deployment.yaml        # App deployment + service
├── app/
│   ├── server.js                  # Node.js app
│   ├── package.json
│   └── Dockerfile
├── Jenkinsfile                    # CI/CD pipeline
├── deploy.sh                      # One-shot deploy
├── destroy.sh                     # Teardown
└── README.md
```

## Estimated Cost

~$250/month (EKS $73 + 2× t3.large $120 + NAT $35 + NLBs $20)

Destroy when not in use: `./destroy.sh`
