#!/usr/bin/env bash

## Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade cert-manager jetstack/cert-manager \
  --install \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait

kubectl apply --server-side -f ./vault-server-tls.yaml

# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm upgrade vault hashicorp/vault \
  --install \
  --namespace vault \
  --values helm-vault-values.yaml \
  --wait

## Wait for pods to be running
kubectl -n vault wait --for=condition=Ready pod -l app.kubernetes.io/name=vault --timeout=10m
