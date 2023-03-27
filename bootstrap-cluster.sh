#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2022 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
clear

# Make sure that we're in the namespace we expect.
kubectl config set-context --current --namespace=default

# Make sure that DEMO_HOST and DEMO_EMAIL are set.
if [[ -z "$DEMO_HOST" ]]; then \
    echo "DEMO_HOST must be set to the hostname you want to use for this demo's DNS-01 challenge." ;\
    exit 1 ;\
fi

if [[ -z "$DEMO_EMAIL" ]]; then \
    echo "DEMO_EMAIL must be set to the email you want to use with Let's Encrypt." ;\
    exit 1 ;\
fi

# Tell demosh to show commands as they're run.
#@SHOW

#### VAULT_CERT_MANAGER_INSTALL_START
bash install-cert-manager-and-vault.sh
bash configure-cert-manager-and-vault.sh
#### VAULT_CERT_MANAGER_INSTALL_END

#@clear

# Install Linkerd, per the quickstart if it is not installed.
#
# NOTE: We aren't installing Grafana here, because we don't need it for this
# demo. Check the Linkerd docs at https://linkerd.io/2.12/tasks/grafana/ for
# more here.
#### LINKERD_INSTALL_START
if ! command -v linkerd &> /dev/null; then \
    echo "linkerd could not be found. Installing it ..." ;\
    curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh ;\
else \
    echo "linkerd is installed" ;\
    linkerd version ;\
fi

linkerd install --crds | kubectl apply -f -
linkerd install --identity-external-issuer | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check
#### LINKERD_INSTALL_END

#@wait
#@clear
# Next up: install Emissary-ingress 3.5.1 as the ingress, if it's not already
# installed. This is mostly following the quickstart, except that we also mesh
# Emissary from the point of installation.
#### EMISSARY_INSTALL_START
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.5.1/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.5.1/emissary-emissaryns.yaml

if ! kubectl get ns emissary >/dev/null 2>&1; then \
    kubectl create namespace emissary && \
    curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_CRDS | \
        kubectl apply -f - ;\
    kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system ;\
    \
    curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_INGRESS | \
        linkerd inject - | \
        kubectl apply -f - ;\
    kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes ;\
else \
    echo "Emissary-ingress is already installed"; \
fi

#### EMISSARY_INSTALL_END

#@wait
#@clear

# Finally, do the most basic Emissary configuration: Listeners for HTTP and
# HTTPS, a wildcard Host, Auth, and a simple Mapping for the Viz dashboard.
#### EMISSARY_CONFIGURE_START
kubectl apply -f k8s/00-bootstrap
#### EMISSARY_CONFIGURE_END

#@wait
#@clear

# Next up: you need a DNS record configured for the DNS-01 challenge to work,
# so we'll output the IP address needed for that.

while true; do \
    EMISSARY_IP=$(kubectl -n emissary get svc  emissary-ingress -o 'go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}') ;\
    if [ -n "$EMISSARY_IP" ]; then \
        echo "Emissary-ingress is available at $EMISSARY_IP" ;\
        break ;\
    else \
        echo "Waiting for Emissary's LoadBalancer to have an IP address..." ;\
        sleep 5 ;\
    fi ;\
done
