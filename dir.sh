#!/bin/bash

# Create the directory structure
mkdir -p .github/workflows
mkdir -p k8s/dev
mkdir -p k8s/prod
mkdir -p src

# Create empty files
touch .github/workflows/ci-cd.yml
touch k8s/dev/deployment.yaml
touch k8s/prod/deployment.yaml
touch src/app.py
touch Dockerfile
touch README.md

echo "Directory structure created successfully in the current directory!"
