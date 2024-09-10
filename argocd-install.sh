#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
EKS_CLUSTER_NAME="demo-eks-cluster"
AWS_PROFILE="raj-private"

# Update kubeconfig for the specified EKS cluster
aws eks --region us-west-2 update-kubeconfig --name $EKS_CLUSTER_NAME --profile $AWS_PROFILE

# Create ArgoCD namespace if it doesn't exist
if ! kubectl get namespace argocd &> /dev/null; then
    echo "Creating ArgoCD namespace..."
    kubectl create namespace argocd
else
    echo "ArgoCD namespace already exists."
fi

# Install or upgrade ArgoCD
echo "Installing/Upgrading ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD pods to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Check ArgoCD server service status
echo "Checking ArgoCD server service status..."
kubectl get svc -n argocd

# Get more details about ArgoCD server service
echo "ArgoCD server service details:"
kubectl describe svc argocd-server -n argocd

# Set up port forwarding
echo "Setting up port forwarding..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PORT_FORWARD_PID=$!

# Give some time for port forwarding to establish
sleep 5

# Retrieve initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null)

if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "Initial admin password not found. It may have been changed or removed."
else
    echo "Initial admin password: $ARGOCD_PASSWORD"
fi

echo "ArgoCD installation/upgrade complete!"
echo "ArgoCD UI is now accessible at https://localhost:8080"
echo "Username: admin"

# Wait for user input before closing
read -p "Press enter to terminate port forwarding and exit..."

# Clean up port forwarding
kill $PORT_FORWARD_PID
