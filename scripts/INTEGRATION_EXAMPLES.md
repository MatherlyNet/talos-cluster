# Integration Examples

This document shows how to integrate the cleanup-app.sh script into various workflows.

## Task Runner Integration (go-task)

Add these tasks to your `.taskfiles/CleanupTasks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://taskfile.dev/schema.json
version: "3"

tasks:
  cleanup:app:
    desc: Clean up Kubernetes application resources
    summary: |
      Discovers and removes all resources for a given application.
      Usage: task cleanup:app -- APP_NAME
      Example: task cleanup:app -- obot
    requires:
      vars: [CLI_ARGS]
    cmd: ./scripts/cleanup-app.sh {{.CLI_ARGS}}
    preconditions:
      - sh: test -x ./scripts/cleanup-app.sh
        msg: cleanup-app.sh script not found or not executable

  cleanup:app:dry-run:
    desc: Preview cleanup without deleting (dry-run mode)
    summary: |
      Shows what would be deleted without making changes.
      Usage: task cleanup:app:dry-run -- APP_NAME
      Example: task cleanup:app:dry-run -- litellm
    requires:
      vars: [CLI_ARGS]
    cmd: ./scripts/cleanup-app.sh --dry-run {{.CLI_ARGS}}

  cleanup:app:auto:
    desc: Automatic cleanup without confirmation prompts
    summary: |
      Dangerous! Deletes resources without asking for confirmation.
      Usage: task cleanup:app:auto -- APP_NAME
      Example: task cleanup:app:auto -- langfuse
    requires:
      vars: [CLI_ARGS]
    cmd: ./scripts/cleanup-app.sh --yes {{.CLI_ARGS}}

  cleanup:app:namespace:
    desc: Clean up app in specific namespace only
    summary: |
      Limits cleanup to a specific namespace.
      Usage: task cleanup:app:namespace -- --namespace NAMESPACE APP_NAME
      Example: task cleanup:app:namespace -- --namespace ai-services obot
    requires:
      vars: [CLI_ARGS]
    cmd: ./scripts/cleanup-app.sh {{.CLI_ARGS}}
```

Then reference it in your main `Taskfile.yaml`:

```yaml
includes:
  cleanup: .taskfiles/CleanupTasks.yaml
```

Usage examples:

```bash
# Preview cleanup
task cleanup:app:dry-run -- obot

# Interactive cleanup with confirmation
task cleanup:app -- obot

# Automatic cleanup (no prompts)
task cleanup:app:auto -- litellm

# Cleanup in specific namespace
task cleanup:app:namespace -- --namespace ai-services langfuse
```

## GitHub Actions Integration

Create `.github/workflows/cleanup-preview.yaml`:

```yaml
name: Cleanup Preview Environment

on:
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    if: startsWith(github.head_ref, 'preview/')

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup kubectl
        uses: azure/setup-kubectl@v4
        with:
          version: 'latest'

      - name: Configure kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > ~/.kube/config

      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq

      - name: Extract app name from branch
        id: extract
        run: |
          APP_NAME="${GITHUB_HEAD_REF#preview/}"
          echo "app_name=${APP_NAME}" >> $GITHUB_OUTPUT

      - name: Cleanup preview deployment
        run: |
          chmod +x ./scripts/cleanup-app.sh
          ./scripts/cleanup-app.sh --yes \
            --namespace preview-${{ steps.extract.outputs.app_name }} \
            ${{ steps.extract.outputs.app_name }}

      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '✅ Preview environment cleaned up successfully'
            })
```

## GitLab CI Integration

Add to `.gitlab-ci.yml`:

```yaml
cleanup:preview:
  stage: cleanup
  image: bitnami/kubectl:latest
  variables:
    APP_NAME: "${CI_COMMIT_REF_SLUG}"
    NAMESPACE: "preview-${CI_COMMIT_REF_SLUG}"
  before_script:
    - apt-get update && apt-get install -y jq
    - mkdir -p ~/.kube
    - echo "${KUBECONFIG_CONTENT}" | base64 -d > ~/.kube/config
  script:
    - chmod +x ./scripts/cleanup-app.sh
    - ./scripts/cleanup-app.sh --yes --namespace "${NAMESPACE}" "${APP_NAME}"
  rules:
    - if: '$CI_MERGE_REQUEST_EVENT_TYPE == "merged"'
      when: always
    - if: '$CI_COMMIT_BRANCH =~ /^preview\//'
      when: manual
  allow_failure: true
```

## Pre-commit Hook

Create `.git/hooks/pre-push` for safety checks:

```bash
#!/usr/bin/env bash

set -euo pipefail

# Prevent pushing if cleanup script is broken
if ! shellcheck scripts/cleanup-app.sh 2>/dev/null; then
  echo "ERROR: cleanup-app.sh has shellcheck violations"
  exit 1
fi

if ! bash -n scripts/cleanup-app.sh; then
  echo "ERROR: cleanup-app.sh has syntax errors"
  exit 1
fi

echo "✓ cleanup-app.sh validation passed"
```

Make it executable:

```bash
chmod +x .git/hooks/pre-push
```

## Makefile Integration

Add to `Makefile`:

```makefile
.PHONY: cleanup-app
cleanup-app: ## Clean up Kubernetes application resources
 @if [ -z "$(APP)" ]; then \
  echo "ERROR: APP variable required. Usage: make cleanup-app APP=obot"; \
  exit 1; \
 fi
 ./scripts/cleanup-app.sh $(ARGS) $(APP)

.PHONY: cleanup-app-dry-run
cleanup-app-dry-run: ## Preview cleanup without deleting
 @if [ -z "$(APP)" ]; then \
  echo "ERROR: APP variable required. Usage: make cleanup-app-dry-run APP=obot"; \
  exit 1; \
 fi
 ./scripts/cleanup-app.sh --dry-run $(APP)

.PHONY: cleanup-app-auto
cleanup-app-auto: ## Automatic cleanup without confirmation
 @if [ -z "$(APP)" ]; then \
  echo "ERROR: APP variable required. Usage: make cleanup-app-auto APP=obot"; \
  exit 1; \
 fi
 ./scripts/cleanup-app.sh --yes $(APP)
```

Usage:

```bash
make cleanup-app-dry-run APP=obot
make cleanup-app APP=litellm
make cleanup-app-auto APP=langfuse ARGS="--namespace ai-services"
```

## ArgoCD Sync Wave Cleanup

Create a Job that runs before deployment:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-old-deployment
  namespace: ai-services
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      serviceAccountName: cleanup-job
      containers:
        - name: cleanup
          image: bitnami/kubectl:latest
          command:
            - /bin/bash
            - -c
            - |
              curl -sfL https://raw.githubusercontent.com/your-repo/main/scripts/cleanup-app.sh \
                -o /tmp/cleanup-app.sh
              chmod +x /tmp/cleanup-app.sh
              /tmp/cleanup-app.sh --yes --namespace ai-services old-app-name
      restartPolicy: Never
  backoffLimit: 2
```

## Flux Kustomization Hook

Create a cleanup Job triggered by Flux:

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: flux-cleanup-hook
  namespace: flux-system
  labels:
    toolkit.fluxcd.io/cleanup: "true"
spec:
  template:
    metadata:
      labels:
        toolkit.fluxcd.io/cleanup: "true"
    spec:
      serviceAccountName: flux-cleanup
      containers:
        - name: cleanup
          image: ghcr.io/fluxcd/flux-cli:v2.2.3
          command:
            - /bin/sh
            - -c
            - |
              # Download cleanup script
              wget -O /tmp/cleanup-app.sh \
                https://raw.githubusercontent.com/your-repo/main/scripts/cleanup-app.sh
              chmod +x /tmp/cleanup-app.sh

              # Run cleanup for old resources
              /tmp/cleanup-app.sh --yes --namespace "${TARGET_NAMESPACE}" "${APP_NAME}"
          env:
            - name: TARGET_NAMESPACE
              value: "ai-services"
            - name: APP_NAME
              value: "deprecated-app"
      restartPolicy: OnFailure
  backoffLimit: 3
```

## Jenkins Pipeline Integration

Add to `Jenkinsfile`:

```groovy
pipeline {
    agent any

    parameters {
        string(name: 'APP_NAME', description: 'Application name to clean up')
        string(name: 'NAMESPACE', defaultValue: '', description: 'Optional: Limit to specific namespace')
        booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'Preview only (no deletion)')
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (!params.APP_NAME) {
                        error('APP_NAME parameter is required')
                    }
                }
            }
        }

        stage('Cleanup Application') {
            steps {
                script {
                    def args = []

                    if (params.DRY_RUN) {
                        args << '--dry-run'
                    } else {
                        args << '--yes'
                    }

                    if (params.NAMESPACE) {
                        args << "--namespace ${params.NAMESPACE}"
                    }

                    args << params.APP_NAME

                    sh """
                        chmod +x ./scripts/cleanup-app.sh
                        ./scripts/cleanup-app.sh ${args.join(' ')}
                    """
                }
            }
        }
    }

    post {
        success {
            echo "Cleanup completed successfully"
        }
        failure {
            echo "Cleanup failed - check logs for details"
        }
    }
}
```

## Docker Container Usage

Build a container image for the cleanup script:

```dockerfile
FROM bitnami/kubectl:latest

RUN apt-get update && \
    apt-get install -y jq curl bash && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/cleanup-app.sh /usr/local/bin/cleanup-app

RUN chmod +x /usr/local/bin/cleanup-app

ENTRYPOINT ["/usr/local/bin/cleanup-app"]
CMD ["--help"]
```

Build and use:

```bash
# Build
docker build -t cleanup-app:latest -f scripts/Dockerfile .

# Run with kubeconfig
docker run --rm \
  -v ~/.kube:/root/.kube:ro \
  cleanup-app:latest --dry-run obot

# Interactive mode
docker run --rm -it \
  -v ~/.kube:/root/.kube:ro \
  cleanup-app:latest
```

## Kubernetes CronJob for Periodic Cleanup

Clean up stale preview environments automatically:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-stale-previews
  namespace: default
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cleanup-cronjob
          containers:
            - name: cleanup
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail

                  # Download cleanup script
                  curl -sfL https://raw.githubusercontent.com/your-repo/main/scripts/cleanup-app.sh \
                    -o /tmp/cleanup-app.sh
                  chmod +x /tmp/cleanup-app.sh

                  # Find preview namespaces older than 7 days
                  cutoff_date=$(date -d '7 days ago' +%s)

                  kubectl get namespaces -l type=preview -o json | \
                  jq -r '.items[] | select(.metadata.creationTimestamp | fromdateiso8601 < '"$cutoff_date"') | .metadata.name' | \
                  while read -r namespace; do
                    app_name="${namespace#preview-}"
                    echo "Cleaning up stale preview: $app_name in $namespace"
                    /tmp/cleanup-app.sh --yes --namespace "$namespace" "$app_name"
                  done
          restartPolicy: OnFailure
      backoffLimit: 2
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cleanup-cronjob
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cleanup-role
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cleanup-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cleanup-role
subjects:
  - kind: ServiceAccount
    name: cleanup-cronjob
    namespace: default
```

## Shell Alias for Quick Access

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Kubernetes cleanup aliases
alias k-cleanup='${PROJECT_ROOT}/scripts/cleanup-app.sh'
alias k-cleanup-dry='${PROJECT_ROOT}/scripts/cleanup-app.sh --dry-run'
alias k-cleanup-auto='${PROJECT_ROOT}/scripts/cleanup-app.sh --yes'

# Function for namespace-scoped cleanup
k-cleanup-ns() {
  if [ $# -lt 2 ]; then
    echo "Usage: k-cleanup-ns NAMESPACE APP_NAME"
    return 1
  fi
  ${PROJECT_ROOT}/scripts/cleanup-app.sh --namespace "$1" "$2"
}
```

Usage:

```bash
k-cleanup-dry obot
k-cleanup litellm
k-cleanup-auto langfuse
k-cleanup-ns ai-services obot
```

## Development Workflow Example

Complete workflow for cleaning up and redeploying:

```bash
#!/usr/bin/env bash
# redeploy-app.sh - Clean up and redeploy application

set -euo pipefail

APP_NAME="${1:?Usage: $0 APP_NAME}"
NAMESPACE="${2:-ai-services}"

echo "1. Suspending Flux reconciliation..."
flux suspend ks "${APP_NAME}" -n flux-system

echo "2. Cleaning up existing resources..."
./scripts/cleanup-app.sh --yes --namespace "${NAMESPACE}" "${APP_NAME}"

echo "3. Updating templates..."
task configure

echo "4. Committing changes..."
git add kubernetes/
git commit -m "feat: redeploy ${APP_NAME}"

echo "5. Pushing to Git..."
git push

echo "6. Resuming Flux reconciliation..."
flux resume ks "${APP_NAME}" -n flux-system

echo "7. Forcing reconciliation..."
task reconcile

echo "✓ Redeployment complete for ${APP_NAME}"
```

Make it executable:

```bash
chmod +x redeploy-app.sh
./redeploy-app.sh obot
```
