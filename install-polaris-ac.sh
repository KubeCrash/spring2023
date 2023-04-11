#!/bin/bash

# Install Polaris as an Admission Controller, setting failure policy to ignore and pointing to values file with custom checks

helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm upgrade --install polaris fairwinds-stable/polaris \
--namespace polaris \
--create-namespace \
--values helm-polaris-values.yaml