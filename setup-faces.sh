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

# Make sure that DEMO_HOST, DEMO_EMAIL, and DEMO_CERT are set.
if [[ -z "$DEMO_HOST" ]]; then \
    echo "DEMO_HOST must be set to the hostname you want to use for this demo's DNS-01 challenge." ;\
    exit 1 ;\
fi

if [[ -z "$DEMO_EMAIL" ]]; then \
    echo "DEMO_EMAIL must be set to the email you want to use with Let's Encrypt." ;\
    exit 1 ;\
fi

if [[ -z "$DEMO_CERT" ]]; then \
    echo "DEMO_CERT must be set to staging, production, or local. See README.md for more info." ;\
    exit 1 ;\
fi

# Next up: you need a DNS record configured for the DNS-01 challenge to work,
# so let's make sure that that's ready here.

EMISSARY_IP=$(kubectl -n emissary get svc emissary-ingress -o 'go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}')

DEMO_IP=$(host -t a "$DEMO_HOST" 2>/dev/null | awk ' { print $NF }')

if [[ "$DEMO_IP" != "$EMISSARY_IP" ]]; then \
    echo "The IP address for $DEMO_HOST is $DEMO_IP, but it should be $EMISSARY_IP." ;\
    exit 1 ;\
fi

# Tell dsh to show commands as they're run.
#@SHOW

# Given that ${DEMO_HOST} correctly points to ${EMISSARY_IP}, we can finish
# configuring cert-manager to get a TLS certificate for Emissary.
kubectl apply -f k8s/01-certs/service-and-mapping.yaml
sed -e "s/<DEMO_HOST>/$DEMO_HOST/g" \
    -e "s/<DEMO_EMAIL>/$DEMO_EMAIL/" < k8s/01-certs/${DEMO_CERT}-cert-template.yaml | \
    kubectl apply -f -

#@wait
#@clear
# Once that's done, install Faces, being sure to inject it into the mesh.
# Install its ServiceProfiles and Mappings too: all of these things are in
# the k8s directory.

#### FACES_INSTALL_START
kubectl create ns faces

linkerd inject k8s/02-faces | kubectl apply -f -
kubectl -n faces wait --for condition=available --timeout=90s deploy --all
#### FACES_INSTALL_END
