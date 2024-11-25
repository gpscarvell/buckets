provider "google" {
  project = "your-project-id"
  region  = "us-central1"
}

resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  name          = each.value.name
  location      = "US"
  storage_class = "STANDARD"

  lifecycle {
    prevent_destroy = true
  }
}


resource "google_storage_bucket_iam_member" "buckets_iam_member" {
  for_each = {
    for bucket, config in var.buckets :
    bucket => flatten([for role in config.iam_roles : for member in role.members : {
      role    = role.role
      member  = member
      bucket  = bucket
    }])
  }

  bucket = google_storage_bucket.buckets[each.value.bucket].name
  role   = each.value.role
  member = each.value.member
}


output "bucket_names" {
  value = [for bucket in google_storage_bucket.buckets : bucket.name]
}


#########


trigger:
  branches:
    include:
      - '*'

pr:
  branches:
    include:
      - '*'

pool:
  vmImage: 'ubuntu-latest'

variables:
  argocd_server: 'your-argocd-server-url' # Replace with your ArgoCD server URL
  repo_url: 'your-repo-url' # Replace with your Git repository URL for
Helm charts
  helm_chart_path: 'charts/your-helm-chart' # Path to your Helm chart directory
  image_registry: 'your-image-registry' # Image registry URL
  image_name: 'your-image-name' # Image name
  image_tag: '$(Build.BuildId)' # Dynamically use BuildId for the new tag
  argocd_app_name:
"$(Build.Repository.Name)-$(Build.SourceBranchName)" # Set app name
based on repo and branch

steps:

- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.x'
    addToPath: true

- script: |
    echo "Installing necessary tools..."
    curl -sSL https://github.com/argoproj/argo-cd/releases/download/v2.3.3/argocd-linux-amd64
-o /usr/local/bin/argocd
    chmod +x /usr/local/bin/argocd
    argocd version
  displayName: 'Install Tools'

# Step 1: Create ArgoCD Application if branch is created
- script: |
    if [[ $(Build.Reason) == "Manual" || $(Build.Reason) ==
"IndividualCI" ]]; then
      echo "Creating ArgoCD application for the new branch..."

      # Set ArgoCD login credentials
      argocd login $(argocd_server) --insecure --username $ARGOCD_USER
--password $ARGOCD_PASSWORD

      # Create ArgoCD application with dynamic name
      argocd app create $(argocd_app_name) \
        --repo $(repo_url) \
        --path $(helm_chart_path) \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace default \
        --revision HEAD \
        --sync-policy automated

      # Sync the application to deploy it
      argocd app sync $(argocd_app_name)
    fi
  displayName: 'Create ArgoCD Application'
  env:
    ARGOCDB_USER: $(argocd_user)
    ARGOCDB_PASSWORD: $(argocd_password)
  condition: and(succeeded(), eq(variables['Build.SourceBranch'],
'refs/heads/main'))

# Step 2: Update Helm chart values file when there’s a PR
- script: |
    if [[ $(Build.Reason) == "PullRequest" ]]; then
      echo "PR detected. Updating Helm chart values file with new image tag..."

      # Check out the repo where Helm chart resides
      git clone $(repo_url) helm-repo
      cd helm-repo

      # Update image tag in values.yaml
      yq eval '.image.tag = "$(image_tag)"' -i $(helm_chart_path)/values.yaml

      # Commit the change to the repo
      git config user.email "azuredevops@yourdomain.com"
      git config user.name "Azure DevOps"
      git add $(helm_chart_path)/values.yaml
      git commit -m "Update image tag to $(image_tag)"
      git push origin HEAD:refs/heads/$(Build.SourceBranchName)
    fi
  displayName: 'Update Helm Chart Values for PR'

