# Flask-ArgoCD-Kubernetes-Deployment

[![CI/CD Pipeline](https://github.com/soodrajesh/Flask-ArgoCD-Kubernetes-Deployment/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/soodrajesh/Flask-ArgoCD-Kubernetes-Deployment/actions/workflows/ci-cd.yml)

This is a deliberately small Flask app used as a vehicle to build out a real GitHub Actions to ArgoCD to Kubernetes deploy path. The app itself does one thing: it returns `Hello from the {ENVIRONMENT} environment!` so you can tell at a glance which overlay (dev or prod) you're actually looking at. Everything interesting here is in the pipeline and the manifests, not the Python.

I built it this way to work through the GitOps split in practice: CI's job stops at building an image and telling ArgoCD what changed, it never runs `kubectl apply` against application manifests directly. ArgoCD owns reconciliation. That separation is the whole point of the exercise, and writing it out below made me find a real gap in my own pipeline (see "What's missing").

## Architecture

```mermaid
flowchart LR
    A["src/app.py (Flask)"] -->|docker build| B[Docker image]
    B -->|docker push| C[(ECR)]
    D["k8s/base, k8s/dev, k8s/prod\n(Kustomize overlays)"]
    E[GitHub Actions\nci-cd.yml] -->|build + push image| C
    E -->|patches kustomization\nand applies Application CR| F["ArgoCD Application\nsample-app-dev / sample-app-prod"]
    D --- E
    F -->|polls git, automated sync\nprune + selfHeal| G[Kubernetes cluster]
    C -->|image pulled by kubelet| G
    G --> H["Deployment: sample-app"]
    H --> I["Service: sample-app-service (LoadBalancer)"]
```

There are two ArgoCD Application definitions in this repo and they're not quite the same thing. `argocd-application.yaml` is a static manifest for a single Application named `sample-app`, always pointed at the `dev` namespace, meant to be applied by hand (`argocd-setup.sh` does this as part of a one-time bootstrap). `.github/workflows/ci-cd.yml` takes a different approach: on every push to `dev` or `main` it builds and pushes the image to ECR, then generates and applies its own Application object named `sample-app-dev` or `sample-app-prod` (branch-dependent), with `repoURL` set dynamically to the calling repo and `targetRevision` pinned to the triggering commit SHA. Both use `syncPolicy.automated` with `prune: true` and `selfHeal: true`, so once an Application exists, ArgoCD reverts manual `kubectl edit`s against it and removes resources dropped from the manifests, without a human clicking "sync."

The `argocd-setup.sh`/`argocd-install.sh` scripts and the static `argocd-application.yaml` are effectively the manual, pre-CI way of standing this up (they also configure ArgoCD's access to a private repo via a token pulled from AWS SSM). The GitHub Actions workflow is the automated version that grew out of that. I kept both in the repo because the manual path is still useful for a first-time bootstrap of ArgoCD itself on a fresh cluster; the workflow doesn't install ArgoCD, only the CD scripts do.

## What's missing

**The CI pipeline has a real gap: it patches placeholders locally but never commits them.** `k8s/dev/kustomization.yaml` and `k8s/prod/kustomization.yaml` contain unresolved `${ECR_REGISTRY}`, `${ECR_REPOSITORY}`, and `${IMAGE_TAG}` placeholders — kustomize doesn't expand these itself. The workflow's "Update Kustomization" step does `kustomize edit set image` and `sed` against the checked-out copy inside the runner, but there's no `git commit` / `git push` step afterward. The ArgoCD Application the workflow then creates is pinned to that same commit SHA, so when ArgoCD actually clones the repo to sync, it sees the original, unresolved kustomization file, not the patched one the runner just printed. As written, the pipeline builds and pushes a real image, but the manifest ArgoCD ends up syncing doesn't reference it correctly. Fixing this needs a decision about how the pipeline should write back to git (bot commit to a deploy branch, a separate manifests repo, image-updater, etc.), so I left it as-is rather than guessing.

There is no environment beyond dev/prod namespaces on one cluster — no separate cluster per environment, no promotion gate between them beyond which branch triggered the build. `EKS_CLUSTER_NAME`, `AWS_PROFILE`, and the SSM parameter path in `argocd-install.sh` / `argocd-setup.sh` are values from my own sandbox account and need to be replaced before this is reusable anywhere else. The app itself runs on Flask's built-in development server (`app.run()`, invoked via `python app.py` in the Dockerfile) rather than a WSGI server like gunicorn; there's also no `requirements.txt` — the Dockerfile installs Flask directly with an unpinned `pip install flask`. `dir.sh` is leftover scaffolding from when I first laid out the project directories; it's not part of the deploy path and can be ignored.

## Project structure

```
.
├── .github/workflows/ci-cd.yml   # builds/pushes image, creates ArgoCD Application per branch
├── Dockerfile
├── argocd-application.yaml       # static bootstrap Application (manual path)
├── argocd-install.sh             # installs ArgoCD on an EKS cluster, port-forwards the UI
├── argocd-service-account.yaml   # RBAC for a service account to drive ArgoCD's Application API
├── argocd-setup.sh               # bootstraps ArgoCD + private repo access + initial sync
├── dir.sh                        # one-off scaffolding script, not part of the deploy flow
├── k8s
│   ├── base
│   │   ├── deployment.yaml       # Deployment + Service (sample-app / sample-app-service)
│   │   └── kustomization.yaml
│   ├── dev
│   │   └── kustomization.yaml    # overlays base, sets ENVIRONMENT=dev
│   └── prod
│       └── kustomization.yaml    # overlays base, sets ENVIRONMENT=prod, replicas=2
└── src
    └── app.py                    # the whole app: one route, one env var
```

## How to run this

Build and run the container locally:

```bash
docker build -t sample-app:local .
docker run -p 5000:5000 -e ENVIRONMENT=local sample-app:local
curl localhost:5000
```

To push a real image and deploy through Kustomize by hand (i.e. doing what the CI workflow currently only half-does), resolve the placeholders yourself before applying:

```bash
export ECR_REGISTRY=<your-account>.dkr.ecr.<region>.amazonaws.com
export ECR_REPOSITORY=sample-app
export IMAGE_TAG=$(git rev-parse --short HEAD)

docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

cd k8s/dev
kustomize edit set image sample-app=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
sed -i '' "s|\${ECR_REGISTRY}|$ECR_REGISTRY|g; s|\${ECR_REPOSITORY}|$ECR_REPOSITORY|g; s|\${IMAGE_TAG}|$IMAGE_TAG|g" kustomization.yaml
cd -

kubectl apply -k k8s/dev
```

Commit that resolved `kustomization.yaml` if you want ArgoCD to pick it up via GitOps rather than applying it out of band.

To bootstrap ArgoCD itself on an EKS cluster (edit `EKS_CLUSTER_NAME` and `AWS_PROFILE` at the top of the script first):

```bash
./argocd-install.sh
```

Then point ArgoCD at this repo (update `repoURL` in `argocd-application.yaml` if you've forked it):

```bash
kubectl apply -f argocd-application.yaml
```

or run `./argocd-setup.sh`, which also wires up a private-repo access token pulled from AWS SSM Parameter Store.
