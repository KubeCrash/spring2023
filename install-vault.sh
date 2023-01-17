#!/usr/bin/env bash

# Source: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-raft

helm repo add hashicorp https://helm.releases.hashicorp.com
# helm repo update
helm upgrade --install vault hashicorp/vault --values helm-vault-values.yaml --namespace vault --create-namespace --wait


## Wait for pods to be running
kubectl -n vault wait --for=jsonpath='{.status.phase}'=Running pod -l app.kubernetes.io/name=vault --timeout=10m

## Init the vault
VAULT_INIT_OUTPUT="$(kubectl -n vault exec -it vault-0 -- vault operator init -key-shares=1  -key-threshold=1  -format=json)"
if [[ "$VAULT_INIT_OUTPUT=" == *"Vault is already initialized"* ]]; then
    echo "Vault already initialized"
else
  echo "$VAULT_INIT_OUTPUT" > vault-keys.json

  VAULT_UNSEAL_KEY="$(jq -r ".unseal_keys_b64[]" vault-keys.json)"

  kubectl -n vault exec vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
  kubectl -n vault exec -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
  kubectl -n vault exec -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200

  kubectl -n vault exec -ti vault-1 -- vault operator unseal "$VAULT_UNSEAL_KEY"
  kubectl -n vault exec -ti vault-2 -- vault operator unseal "$VAULT_UNSEAL_KEY"
fi
