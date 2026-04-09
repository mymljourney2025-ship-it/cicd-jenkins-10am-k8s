#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy everything from scratch
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# ─── Step 1: Terraform ───
step "1/5 — Terraform Init & Apply"
cd terraform
terraform init
terraform apply -auto-approve
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
ECR_REPO=$(terraform output -raw ecr_repo_url)
ACCOUNT_ID=$(terraform output -raw account_id)
REGION=$(terraform output -raw region)
cd ..
log "Infrastructure created"

# ─── Step 2: Configure kubectl ───
step "2/5 — Configure kubectl"
aws eks update-kubeconfig --region "${REGION}" --name "${EKS_CLUSTER}"
kubectl get nodes
log "kubectl configured"

# ─── Step 3: Deploy Jenkins ───
step "3/5 — Deploy Jenkins to EKS"
kubectl apply -f jenkins/jenkins-deployment.yaml
echo "Waiting for Jenkins pod..."
kubectl wait --for=condition=ready pod -l app=jenkins -n jenkins --timeout=300s || true
JENKINS_URL=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
log "Jenkins deployed"

# ─── Step 4: Build & Push initial image ───
step "4/5 — Build & Push App Image to ECR"
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

cd app
docker build -t "${ECR_REPO}:1" -t "${ECR_REPO}:latest" .
docker push "${ECR_REPO}:1"
docker push "${ECR_REPO}:latest"
cd ..
log "Image pushed to ECR"

# ─── Step 5: Deploy App ───
step "5/5 — Deploy App to EKS"
sed "s|IMAGE_PLACEHOLDER|${ECR_REPO}:1|g; s|VERSION_PLACEHOLDER|1|g" \
    k8s/app-deployment.yaml | kubectl apply -f -

kubectl rollout status deployment/myapp -n myapp --timeout=120s || true
APP_URL=$(kubectl get svc myapp -n myapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

# ─── Done ───
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  DEPLOYMENT COMPLETE                                  ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  EKS Cluster : ${EKS_CLUSTER}${NC}"
echo -e "${GREEN}║  ECR Repo    : ${ECR_REPO}${NC}"
echo -e "${GREEN}║  Jenkins URL : http://${JENKINS_URL}:8080${NC}"
echo -e "${GREEN}║  App URL     : http://${APP_URL}${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Jenkins password:                                    ║${NC}"
echo -e "${GREEN}║  kubectl exec -n jenkins deploy/jenkins -- \\          ║${NC}"
echo -e "${GREEN}║    cat /var/jenkins_home/secrets/initialAdminPassword ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
