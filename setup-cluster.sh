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

# Tell dsh to show commands as they're run.
#@SHOW

#### VAULT_CERT_MANAGER_INSTALL_START
bash install-cert-manager-and-vault.sh
bash configure-cert-manager-and-vault.sh
#### VAULT_CERT_MANAGER_INSTALL_END

#@clear
# Install Linkerd, per the quickstart if it is not installed
#### LINKERD_INSTALL_START
if ! command -v linkerd &> /dev/null
then
    echo "linkerd could not be found. Installing it ..."
    curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
else
    echo "linkerd is installed"
    linkerd version
fi

linkerd install --crds | kubectl apply -f -
linkerd install --identity-external-issuer | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check
#### LINKERD_INSTALL_END

# # Next up, install Grafana, since we don't get that by default in 2.12.
# #### GRAFANA_INSTALL_START
# helm repo add grafana https://grafana.github.io/helm-charts
# helm install grafana -n grafana --create-namespace grafana/grafana \
#   -f https://raw.githubusercontent.com/linkerd/linkerd2/main/grafana/values.yaml \
#   --wait
# linkerd viz install --set grafana.url=grafana.grafana:3000 | kubectl apply -f -
# linkerd check
# #### GRAFANA_INSTALL_END

#@wait
#@clear
# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart, but we force every Deployment to one replica to reduce the load
# on k3d.

#### EMISSARY_INSTALL_START
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_CRDS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system

curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_INGRESS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    linkerd inject - | \
    kubectl apply -f -

kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
#### EMISSARY_INSTALL_END

#@wait
#@clear
# Finally, configure Emissary for HTTP - not HTTPS! - routing to our cluster.
#### EMISSARY_CONFIGURE_START
kubectl apply -f emissary-yaml
#### EMISSARY_CONFIGURE_END

kubectl apply -f cert-manager-yaml

#@wait
#@clear
# Once that's done, install Faces, being sure to inject it into the mesh.
# Install its ServiceProfiles and Mappings too: all of these things are in
# the k8s directory.

#### FACES_INSTALL_START
kubectl create ns faces

linkerd inject k8s/01-base | kubectl apply -f -
kubectl -n faces wait --for condition=available --timeout=90s deploy --all
#### FACES_INSTALL_END
