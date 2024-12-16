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


###########




trigger:
- main  # Trigger the pipeline on changes to the main branch (or
replace with your branch)

pool:
  vmImage: 'ubuntu-latest'

variables:
  PROJECT_ID: 'your-gcp-project-id'  # Replace with your GCP Project ID
  REGION: 'your-gcp-region'  # Replace with your GCP region
  GKE_CLUSTER: 'your-gke-cluster-name'  # Replace with your GKE
Autopilot cluster name
  GKE_ZONE: 'your-gke-zone'  # Replace with your GKE zone (e.g.,
'us-central1-a')

steps:

# Step 1: Install Helm and Kubernetes External Secrets (KES)
- task: HelmInstaller@1
  displayName: 'Install Helm'
  inputs:
    helmVersionToInstall: 'v3.8.0'  # Specify the Helm version you need

- script: |
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install kubernetes-external-secrets
external-secrets/kubernetes-external-secrets \
      --namespace kube-system \
      --create-namespace
  displayName: 'Install Kubernetes External Secrets'

# Step 2: Authenticate to GCP
- task: GoogleCloudSDK@0
  displayName: 'Authenticate to Google Cloud'
  inputs:
    credentialsJson: '$(GOOGLE_CREDENTIALS_JSON)'  # The service
account JSON key is stored as a pipeline secret

# Step 3: Create the Google Cloud Service Account (GSA)
- script: |
    gcloud iam service-accounts create gke-secret-manager-access \
      --display-name "GKE Secret Manager Access"
  displayName: 'Create Google Cloud Service Account (GSA)'

# Step 4: Grant permissions to the GSA to access Google Secret Manager
- script: |
    gcloud projects add-iam-policy-binding $(PROJECT_ID) \
      --member="serviceAccount:gke-secret-manager-access@$(PROJECT_ID).iam.gserviceaccount.com"
\
      --role="roles/secretmanager.secretAccessor"
  displayName: 'Grant permissions to the GSA'

# Step 5: Create the Kubernetes Service Account (KSA)
- script: |
    kubectl create serviceaccount gke-secret-manager-ksa --namespace default
  displayName: 'Create Kubernetes Service Account (KSA)'

# Step 6: Associate the KSA with the GSA using Workload Identity
- script: |
    gcloud iam service-accounts add-iam-policy-binding \
      gke-secret-manager-access@$(PROJECT_ID).iam.gserviceaccount.com \
      --member="serviceAccount:$(PROJECT_ID).svc.id.goog[default/gke-secret-manager-ksa]"
\
      --role="roles/secretmanager.secretAccessor"
  displayName: 'Associate KSA with GSA using Workload Identity'

# Step 7: Apply the SecretStore resource
- script: |
    cat <<EOF | kubectl apply -f -
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: gke-secret-manager
      namespace: kube-system
    spec:
      provider:
        gcpSecretManager:
          projectID: $(PROJECT_ID)
          auth:
            workloadIdentity:
              serviceAccountRef:
                name: gke-secret-manager-ksa
    EOF
  displayName: 'Create SecretStore resource'

# Step 8: Apply the ExternalSecret resource
- script: |
    cat <<EOF | kubectl apply -f -
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: my-secret
      namespace: default
    spec:
      secretStoreRef:
        name: gke-secret-manager
      target:
        name: my-k8s-secret
        creationPolicy: Owner
      data:
        - secretKey: my-secret
          remoteRef:
            key: my-secret
    EOF
  displayName: 'Create ExternalSecret resource'

# Step 9: Verify the Kubernetes Secret
- script: |
    kubectl get secret my-k8s-secret -o yaml
  displayName: 'Verify Kubernetes Secret'


############3



trigger:
- main  # Trigger the pipeline on changes to the main branch

pool:
  vmImage: 'ubuntu-latest'

variables:
  PROJECT_ID: 'your-gcp-project-id'  # Replace with your GCP Project ID
  GKE_CLUSTER: 'your-gke-cluster-name'  # Replace with your GKE
Autopilot cluster name
  GKE_ZONE: 'your-gke-zone'  # Replace with your GKE zone
  ARGOCD_NAMESPACE: 'argocd'
  ARGOCD_PASSWORD_SECRET_NAME: 'argocd-admin-password'  # Name of the
secret in Google Secret Manager
  SECRET_STORE_NAME: 'gke-secret-manager'  # SecretStore resource name
  EXTERNAL_SECRET_NAME: 'argocd-admin-password'  # ExternalSecret resource name

steps:

# Step 1: Install Helm
- task: HelmInstaller@1
  displayName: 'Install Helm'
  inputs:
    helmVersionToInstall: 'v3.8.0'

# Step 2: Install Kubernetes External Secrets (KES)
- script: |
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install kubernetes-external-secrets
external-secrets/kubernetes-external-secrets \
      --namespace kube-system \
      --create-namespace
  displayName: 'Install Kubernetes External Secrets'

# Step 3: Authenticate to GCP using Service Account JSON Key
- task: GoogleCloudSDK@0
  displayName: 'Authenticate to Google Cloud'
  inputs:
    credentialsJson: '$(GOOGLE_CREDENTIALS_JSON)'  # The service
account JSON key is stored as a pipeline secret

# Step 4: Install ArgoCD using Helm
- script: |
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
    helm install argo-cd argo/argo-cd --namespace $(ARGOCD_NAMESPACE)
--create-namespace
  displayName: 'Install ArgoCD'

# Step 5: Create Google Cloud Service Account (GSA) to access Google
Secret Manager
- script: |
    gcloud iam service-accounts create gke-secret-manager-access \
      --display-name "GKE Secret Manager Access"
  displayName: 'Create Google Cloud Service Account (GSA)'

# Step 6: Grant the necessary permissions to the GSA to access Google
Secret Manager
- script: |
    gcloud projects add-iam-policy-binding $(PROJECT_ID) \
      --member="serviceAccount:gke-secret-manager-access@$(PROJECT_ID).iam.gserviceaccount.com"
\
      --role="roles/secretmanager.secretAccessor"
  displayName: 'Grant permissions to the GSA'

# Step 7: Create Kubernetes Service Account (KSA) and associate it
with the GSA using Workload Identity
- script: |
    kubectl create serviceaccount gke-secret-manager-ksa --namespace default
    gcloud iam service-accounts add-iam-policy-binding \
      gke-secret-manager-access@$(PROJECT_ID).iam.gserviceaccount.com \
      --member="serviceAccount:$(PROJECT_ID).svc.id.goog[default/gke-secret-manager-ksa]"
\
      --role="roles/secretmanager.secretAccessor"
  displayName: 'Create and associate KSA with GSA'

# Step 8: Create SecretStore resource to connect Kubernetes External
Secrets with Google Secret Manager
- script: |
    cat <<EOF | kubectl apply -f -
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: $(SECRET_STORE_NAME)
      namespace: kube-system
    spec:
      provider:
        gcpSecretManager:
          projectID: $(PROJECT_ID)
          auth:
            workloadIdentity:
              serviceAccountRef:
                name: gke-secret-manager-ksa
    EOF
  displayName: 'Create SecretStore resource'

# Step 9: Create ExternalSecret to sync the ArgoCD admin password from
Google Secret Manager
- script: |
    cat <<EOF | kubectl apply -f -
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: $(EXTERNAL_SECRET_NAME)
      namespace: $(ARGOCD_NAMESPACE)
    spec:
      secretStoreRef:
        name: $(SECRET_STORE_NAME)
      target:
        name: argocd-secret
        creationPolicy: Owner
      data:
        - secretKey: admin.password
          remoteRef:
            key: $(ARGOCD_PASSWORD_SECRET_NAME)  # The name of the
secret in Google Secret Manager
    EOF
  displayName: 'Create ExternalSecret for ArgoCD Admin Password'

# Step 10: Verify the Kubernetes Secret created by ExternalSecrets
- script: |
    kubectl get secret argocd-secret -n $(ARGOCD_NAMESPACE) -o yaml
  displayName: 'Verify ArgoCD Kubernetes Secret'

# Step 11: Patch ArgoCD Deployment to Use the Secret as Admin Password
- script: |
    kubectl patch deployment argocd-server -n $(ARGOCD_NAMESPACE)
--patch "$(cat <<EOF
    spec:
      template:
        spec:
          containers:
          - name: argocd-server
            env:
            - name: ARGOCD_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: argocd-secret
                  key: admin.password
    EOF
    )"
  displayName: 'Patch ArgoCD Deployment with Admin Password'





##########


trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  KUBECONFIG_PATH: '$(System.DefaultWorkingDirectory)/kubeconfig'
  ARGOCD_APPLICATION_FILE: 'argocd-application.yaml'
  HELM_VALUES_FILE: 'values.yaml'

stages:
- stage: Deploy
  displayName: Deploy ArgoCD Application
  jobs:
  - job: DeployArgoCDApp
    displayName: Deploy ArgoCD Application YAML
    steps:
    - task: DownloadSecureFile@1
      displayName: Download kubeconfig
      inputs:
        secureFile: 'kubeconfig' # Replace with your secure file name

    - script: |
        mkdir -p ~/.kube
        cp $(KUBECONFIG_PATH) ~/.kube/config
        chmod 600 ~/.kube/config
      displayName: Configure kubeconfig

    - script: |
        cat <<EOF > $(ARGOCD_APPLICATION_FILE)
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: my-helm-app
          namespace: argocd
        spec:
          project: default
          source:
            repoURL: https://github.com/my-org/my-repo.git
            targetRevision: main
            path: charts/my-helm-chart
            helm:
              valueFiles:
              - $(HELM_VALUES_FILE)
          destination:
            server: https://kubernetes.default.svc
            namespace: my-namespace
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
        EOF
      displayName: Generate ArgoCD Application YAML

    - script: |
        cat <<EOF > $(HELM_VALUES_FILE)
        replicaCount: 3
        image:
          repository: my-docker-repo/my-app
          tag: latest
        service:
          type: ClusterIP
          port: 8080
        EOF
      displayName: Generate Helm Values File

    - task: Kubernetes@1
      displayName: Apply ArgoCD Application YAML
      inputs:
        connectionType: 'KubeConfig'
        kubeconfig: '$(KUBECONFIG_PATH)'
        command: 'apply'
        arguments: '-f $(ARGOCD_APPLICATION_FILE)'

    - script: |
        kubectl get applications.argoproj.io -n argocd
      displayName: Verify Deployment


######################

trigger:
  branches:
    include:
      - feature/*

pool:
  vmImage: 'ubuntu-latest'

variables:
  GITHUB_REPO: '<github-org>/<app-of-apps-repo>'
  FEATURE_BRANCH_YAML: ''
  GITHUB_TOKEN: $(githubToken) # GitHub PAT stored in ADO variable group
  ARTIFACTORY_REPO_URL: '<artifactory-oci-repo-url>' # Replace with the actual OCI repo URL
  ARTIFACTORY_NAMESPACE: '<k8s-namespace>' # Replace with desired namespace in Kubernetes

steps:
  # Step 1: Determine feature branch name from pipeline branch
  - script: |
      echo "##vso[task.setvariable variable=FEATURE_BRANCH_NAME]$(echo ${BUILD_SOURCEBRANCH#refs/heads/})"
      echo "##vso[task.setvariable variable=FEATURE_BRANCH_YAML]argocd/feature-$(echo ${BUILD_SOURCEBRANCH#refs/heads/}).yaml"
    displayName: "Determine Feature Branch Name"

  # Step 2: Checkout code
  - task: Checkout@1

  # Step 3: Clone the GitHub App of Apps repository
  - script: |
      git clone https://$(GITHUB_TOKEN)@github.com/${{ variables.GITHUB_REPO }} repo
      cd repo
    displayName: "Clone GitHub App of Apps Repo"

  # Step 4: Check if the ArgoCD YAML for the feature branch exists
  - script: |
      cd repo
      if [ -f "${FEATURE_BRANCH_YAML}" ]; then
        echo "Feature branch YAML already exists. Skipping creation."
        exit 0
      fi
    displayName: "Check if Feature Branch YAML Exists"

  # Step 5: Generate the ArgoCD YAML if it doesn't exist
  - script: |
      cd repo
      cat <<EOF > $FEATURE_BRANCH_YAML
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: feature-${FEATURE_BRANCH_NAME}
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: oci://${ARTIFACTORY_REPO_URL}
          chart: feature-${FEATURE_BRANCH_NAME}
          targetRevision: latest
        destination:
          server: https://kubernetes.default.svc
          namespace: ${ARTIFACTORY_NAMESPACE}
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
      EOF
    displayName: "Generate Feature Branch YAML for Artifactory OCI Repository"

  # Step 6: Commit and push the YAML to the GitHub App of Apps repository
  - script: |
      cd repo
      git config user.name "ADO Pipeline"
      git config user.email "pipeline@devops.com"
      git add ${FEATURE_BRANCH_YAML}
      git commit -m "Add ArgoCD config for feature branch: $FEATURE_BRANCH_NAME"
      git push origin main
    displayName: "Commit and Push YAML"


