#!/bin/bash

# Set variables
EKS_CLUSTER_NAME="demo-eks-cluster"
AWS_PROFILE="raj-private"
GITHUB_REPO="https://github.com/soodrajesh/argocd-k8s-project1.git"
GITHUB_TOKEN_PARAM_NAME="/soodrajesh-github-token"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install required tools
if ! command_exists kubectl; then
    echo "kubectl not found. Please install kubectl and try again."
    exit 1
fi

if ! command_exists aws; then
    echo "AWS CLI not found. Please install AWS CLI and try again."
    exit 1
fi

# Fetch GitHub token from AWS Parameter Store
echo "Fetching GitHub token from AWS Parameter Store..."
GITHUB_TOKEN=$(aws ssm get-parameter --name "$GITHUB_TOKEN_PARAM_NAME" --with-decryption --query "Parameter.Value" --output text --profile $AWS_PROFILE)

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Failed to retrieve GitHub token from AWS Parameter Store. Please check the parameter name and your AWS permissions."
    exit 1
fi

# Update kubeconfig for the EKS cluster
echo "Updating kubeconfig for EKS cluster..."
aws eks --region $(aws configure get region --profile $AWS_PROFILE) update-kubeconfig --name $EKS_CLUSTER_NAME --profile $AWS_PROFILE

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD pods to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"

# Install ArgoCD CLI
if ! command_exists argocd; then
    echo "Installing ArgoCD CLI..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install argocd
    else
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
    fi
fi

# Create ArgoCD Application
echo "Creating ArgoCD Application..."
cat <<EOF > argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $GITHUB_REPO
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

kubectl apply -f argocd-application.yaml

# Configure ArgoCD to access private GitHub repository
echo "Configuring ArgoCD to access private GitHub repository..."
kubectl create secret generic github-token --from-literal=token=$GITHUB_TOKEN -n argocd
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data": {"repositories": "[{\"url\": \"'$GITHUB_REPO'\", \"passwordSecret\": {\"name\": \"github-token\", \"key\": \"token\"}}]"}}'

# Sync the application
echo "Syncing the application..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PID=$!
sleep 5
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure
argocd app sync sample-app
kill $PID

echo "ArgoCD setup complete!"
