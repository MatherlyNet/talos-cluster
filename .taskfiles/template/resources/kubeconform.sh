#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR=$1

[[ -z "${KUBERNETES_DIR}" ]] && echo "Kubernetes location not specified" && exit 1

kustomize_args=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"
kubeconform_args=(
    "-strict"
    "-ignore-missing-schemas"
    "-skip"
    "Gateway,HTTPRoute,Secret"
    "-schema-location"
    "default"
    "-schema-location"
    "https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

# Use process substitution to avoid subshell exit code masking
echo "=== Validating standalone manifests in ${KUBERNETES_DIR}/flux ==="
flux_files=()
while IFS= read -r -d $'\0' file; do
    flux_files+=("$file")
done < <(find "${KUBERNETES_DIR}/flux" -maxdepth 1 -type f -name '*.yaml' -print0)
for file in "${flux_files[@]}"; do
    kubeconform "${kubeconform_args[@]}" "${file}" || exit 1
done

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/flux ==="
flux_kustomizations=()
while IFS= read -r -d $'\0' file; do
    flux_kustomizations+=("$file")
done < <(find "${KUBERNETES_DIR}/flux" -type f -name "$kustomize_config" -print0)
for file in "${flux_kustomizations[@]}"; do
    echo "=== Validating kustomizations in ${file/%$kustomize_config} ==="
    kustomize build "${file/%$kustomize_config}" "${kustomize_args[@]}" | kubeconform "${kubeconform_args[@]}" || exit 1
done

echo "=== Validating kustomizations in ${KUBERNETES_DIR}/apps ==="
app_kustomizations=()
while IFS= read -r -d $'\0' file; do
    app_kustomizations+=("$file")
done < <(find "${KUBERNETES_DIR}/apps" -type f -name "$kustomize_config" -print0)
for file in "${app_kustomizations[@]}"; do
    echo "=== Validating kustomizations in ${file/%$kustomize_config} ==="
    kustomize build "${file/%$kustomize_config}" "${kustomize_args[@]}" | kubeconform "${kubeconform_args[@]}" || exit 1
done
