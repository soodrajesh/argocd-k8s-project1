# Sample ArgoCD Application

This is a sample application deployed using ArgoCD.

## Application Structure

- `src/app.py`: A simple Flask application that displays a greeting message.
- `Dockerfile`: Used to build the Docker image for the application.
- `k8s/`: Contains Kubernetes manifests for both dev and prod environments.

## Deployment

This application is automatically deployed using GitHub Actions and ArgoCD. The workflow is as follows:

1. On push to `dev` or `main` branch, GitHub Actions builds a Docker image and pushes it to ECR.
2. The ArgoCD application is updated with the new image tag.
3. ArgoCD syncs the application, deploying it to the appropriate environment (dev or prod).

## Viewing the Application

After deployment:

1. Log into your ArgoCD UI.
2. Find the `sample-app` application.
3. Check the sync status and health of the application.
4. To access the application, get the LoadBalancer URL:
   - For dev: `kubectl get svc sample-app-service -n dev`
   - For prod: `kubectl get svc sample-app-service -n prod`
5. Open the LoadBalancer URL in a web browser to see the application running.

## Troubleshooting

If you encounter issues:

1. Check the ArgoCD UI for sync errors.
2. Review the logs of the deployed pods:
   - `kubectl logs -n <dev/prod> -l app=sample-app`
3. Ensure that the ECR repository is accessible and the image exists.
