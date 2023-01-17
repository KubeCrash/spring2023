#!/usr/bin/env bash

VAULT_UNSEAL_KEY="$(jq -r ".unseal_keys_b64[]" vault-keys.json)"
kubectl -n vault exec vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl -n vault exec -ti vault-1 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl -n vault exec -ti vault-2 -- vault operator unseal "$VAULT_UNSEAL_KEY"
