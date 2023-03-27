# KubeCrash Spring 2023: Multiple Projects, One Goal

This is the "Multiple Projects, One Goal" demo for KubeCrash Spring 2023.
Here, we show [Emissary-ingress], [Linkerd], [cert-manager], and [Polaris] all
working together in support of the [Faces] application.

[Emissary-ingress]: https://www.getambassador.io/products/api-gateway
[Linkerd]: https://linkerd.io/
[cert-manager]: https://cert-manager.io/
[Polaris]: https://www.fairwinds.com/polaris
[Faces]: https://github.com/BuoyantIO/faces-demo

The Faces application presents a single-page web GUI that presents a grid of
cells, each of which should show a smiling face on a green background. (In
many cases, Faces is deliberately installed in a broken state to demo
resilience features. For "Multiple Projects, One Goal", we install Faces in a
working state.)

Note that many of the shell scripts here are written to work well with
[demosh]. If you're not using [demosh] to run them, just ignore any comments
starting with `#@`.

[demosh]: https://github.com/BuoyantIO/demosh

## Deploying Everything

Most of "Multiple Projects, One Goal" is straightforward. The exception is
Emissary-ingress' TLS termination certificate. To properly use cert-manager to
provide this certificate - which is an important part of the demo! - you'll
need:

- a cluster that supports globally-routable Services of type `LoadBalancer`
  (which almost always means a cluster from a cloud provider); and

- a DNS A record configured to point to the globally-routable IP address of
  the `emissary-ingress` Service in the `emissary` namespace.

There's a bit of a chicken-and-egg problem here: you have to partially deploy
the demo in order to get the IP address to finish deploying! So deploying is
split into several steps.

### Using a Globally-Routable Cluster

Start by exporting `$DEMO_HOST`, `$DEMO_EMAIL`, and '$DEMO_CERT`:

- `$DEMO_HOST` must be the hostname you'll use for your Emissary-ingress
  LoadBalancer (you can choose the name before knowing the IP address, it's
  OK)
- `$DEMO_EMAIL` must be the email address you'll use with Let's Encrypt.
- `$DEMO_CERT` must be either `staging` or `production`, to select whether to
  use the Let's Encrypt's staging environment or their production environment.
  **WHEN IN DOUBT, USE STAGING**: you've have to click through a scary TLS
  warning in your browser, but you'll be able to recreate your cluster as much
  as you want. With `DEMO_CERT=production`, you can only renew the cluster
  five times per week, so only switch to that once you're pretty sure you'll
  be able to leave your cluster running.

After getting your cluster set up:

1. Run `bootstrap-cluster.sh` to install Vault, cert-manager,
   Emissary-ingress, and Linkerd.
2. Make sure the DNS for `$DEMO_HOST` is set up correctly.
3. Run `setup-faces.sh` to finish setting up the demo.

(`bootstrap-cluster.sh` and `setup-faces.sh` run well with [demosh], but
they're fine with `bash` as well. Realize that all the `#@` comments are
special to [demosh] and ignored by `bash`.)

### Using a Local Cluster

If you need to use a local cluster like `k3d`, you'll still start by exporting
`$DEMO_HOST`, `$DEMO_EMAIL`, and `$DEMO_CERT`:

- `$DEMO_HOST` should be `demo.127-0-0-1.sslip.io`
- `$DEMO_EMAIL` can be, really, anything
- `$DEMO_CERT` must be `local`.

and then run `bootstrap-cluster.sh` and `setup-faces.sh`.

Note that you'll be using an untrusted certificate for Emissary's TLS
termination in this mode, so your browser will complain. To shut up the
complaints, you can grab the root CA from Vault using
`curl localhost:8200/v1/pki/ca > ~/tmp/ca.pem`, then add the cert in
`/tmp/ca.pem` to your local turst store.

## After Deploying

Play around! The Faces demo will be available at `https://$DEMO_HOST/faces/`,
with the Linkerd Viz dashboard at `https://$DEMO_HOST/`.

- You'll need to authenticate through Emissary to reach either -- use username
  `username` and password `password` (I know, I know, very secure).

- To disable authentication, use `kubectl delete authservice -n emissary
  authentication`

- To run the Linkerd zero-trust demo, check out [LINKERD_DEMO.md]. The easiest
  way to use that is to run it with [demosh].

- To reset everything after the Linkerd zero-trust demo, run

   ```
   kubectl delete ns faces
   kubectl create ns faces
   linkerd inject k8s/02-faces | kubectl apply -f -
   kubectl -n faces wait --for condition=available --timeout=90s deploy --all
   ```

[Linkerd]: https://linkerd.io
[Emissary-ingress]: https://www.getambassador.io/docs/emissary/
[LINKERD_DEMO.md]: LINKERD_DEMO.md
[demosh]: https://github.com/BuoyantIO/demosh
[Polaris]: https://polaris.docs.fairwinds.com
[cert-manager]: https://cert-manager.io
---

#### DEMO HOOKS

There are many `#@` comments in the shell scripts; those are hooks to be
interpreted by external software. You can safely ignore them for now.
