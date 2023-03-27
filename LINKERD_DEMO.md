<!-- @clear -->

Make sure that DEMO_HOST is set before we start.

```bash
set -e

if [[ -z "$DEMO_HOST" ]]; then \
    echo "DEMO_HOST must be set to the hostname to use to reach the demo." ;\
    exit 1 ;\
fi
```

<!-- @SHOW -->

Start by opening a browser window to https://${DEMO_HOST}/faces/.

You'll need to authenticate using username `username` and password `password`;
after that, you should see the Faces app running, showing lots of smileys on
green backgrounds. Note also that we can reach through Emissary directly to
the backend Faces services:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/face/
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/smiley/
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/color/
```

A good way to start for zero trust is by completely locking down access to the
`faces` namespace: this lets us be sure of the whole least-privilege concept.
(Really should do Emissary too, but let's concentrate on the Faces app for
now.)

```bash
kubectl annotate ns faces config.linkerd.io/default-inbound-policy=deny
```

We need to restart everything in the namespace for that to take effect...

```bash
kubectl rollout restart -n faces deployment
kubectl rollout status -n faces deployment
```

At this point, the Faces app will be _completely_ nonfunctional: it will show
all grimacing faces on grey backgrounds, meaning that the GUI can't talk to
anything at all. This is very secure but honestly kind of pointless: what good
is an app you can't use?

So we'll start by granting Emissary some minimal access to reach in. If we
look back at the architecture diagram, the web browser needs two things:

1. The browser needs to reach through Emissary to the `faces-gui` workload, to
   load the page with the Faces GUI.
2. The Faces GUI then needs to reach through Emissary to the `faces` workload,
   to fetch all the smiley faces.

To let Emissary do this, we'll create a Server definition called
`faces-front-end` that encompasses both the `faces-gui` and `face` workloads:

```bash
bat k8s/03-linkerd-zero-trust/faces-front-end.yaml
kubectl apply -f k8s/03-linkerd-zero-trust/faces-front-end.yaml
```

Then we can associate an AuthorizationPolicy with this Server, that allows
requests from Emissary's identity:

```bash
bat k8s/03-linkerd-zero-trust/allow-emissary.yaml
```

(We're saying nothing at all about the network here: what matters is the
workload identity that's assigned to Emissary.)

Let's apply this and see what happens in the Faces GUI:

```bash
kubectl apply -f k8s/03-linkerd-zero-trust/allow-emissary.yaml
```

So... things are different now, but they're not good. Rather than seeing the
grimacing faces that show that Emissary can't talk to the `face` service at
all, we see cursing faces on a grey background, meaning that the `face`
service can't talk to the `smiley` and `color` services. This makes sense,
since we locked down the whole namespace, and haven't yet told Linkerd to
allow those requests.

Once again, we can create a single Server that encompasses the `smiley` and
`color` workloads. We'll call that one `faces-back-end`:

```bash
bat k8s/03-linkerd-zero-trust/faces-back-end.yaml
kubectl apply -f k8s/03-linkerd-zero-trust/faces-back-end.yaml
```

...and, likewise, we'll add an AuthorizationPolicy to allow the `face`
workload - and _only_ the `face` workload - to talk to it:

```bash
bat k8s/03-linkerd-zero-trust/allow-face-to-back-end.yaml
kubectl apply -f k8s/03-linkerd-zero-trust/allow-face-to-back-end.yaml
```

At this point the Faces application should be happy again, with minimal
privileges granted to the workloads in our cluster. Let's check to make sure
that Emissary no longer has access to the `smiley` and `color` services:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/face/
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/smiley/
curl -s -o /dev/null -w "%{http_code}\n" -u username:password \
     https://${DEMO_HOST}/color/
```

One other point: the `face` workload responds to two different paths: the GUI
uses the `/cell/...` path to fetch cells to display, but we can also use the
`/rl` path to see how many RPS the `face` workload thinks it's seeing:

```bash
curl -s -u username:password https://${DEMO_HOST}/face/rl | jq
```

This is just for debugging, so we should really not allow access to it from
outside. We can use an `HTTPRoute` to close that down:

```bash
bat k8s/03-linkerd-zero-trust/face-only-root.yaml
kubectl apply -f k8s/03-linkerd-zero-trust/face-only-root.yaml
```

The Faces application is still working fine - good! - but if we try the `/rl`
path again, we'll get a 404:

```bash
curl -v -u username:password https://${DEMO_HOST}/face/rl
```

(This is actually probably _too_ broadly restrictive, since it won't let _any_
workload use the `/rl` path. We could couple this with an AuthorizationPolicy
to open it up just a bit, but for now we'll just be Draconian about it.)

<!-- @SHOW -->

An additional note: locking down the namespace actually broke stats, too:

```bash
linkerd viz stat ns/faces
```

If we switch over to the Viz dashboard, we'll see that it doesn't work either.

This is obviously not ideal. To reenable stats, we need a Server and an
AuthorizationPolicy with MeshTLSAuthentication to allow viz traffic:

```bash
bat k8s/03-linkerd-zero-trust/admin-server.yaml
kubectl apply -f k8s/03-linkerd-zero-trust/admin-server.yaml
bat k8s/03-linkerd-zero-trust/allow-viz.yaml
```

(The AuthorizationPolicy doesn't reference the Server because it doesn't need
to: if the `targetRef` is a Namespace, any traffic matching a Server in that
namespace will be affected.)

```bash
kubectl apply -f k8s/03-linkerd-zero-trust/allow-viz.yaml
```

What do we see in stats now? (Note that it might take a few seconds for
meaningful things to show up here.)

```bash
watch "linkerd viz stat ns/faces"
```

If we flip back to the Viz dashboard at this point, too, we'll see that it
works.

# ONE MORE THING

Remember that HTTPRoute we used to block access to anything but one path on
the `face` service? As of 2.13, HTTPRoute is much more powerful than that.
Here's a quick example of using one to do a canary deployment deep in the call
stack:

```bash
bat k8s/03-linkerd-zero-trust/smiley-canary.yaml
```

If we apply that - with no application changes - half the cells will get the
"normal" smiley from the `smiley` workload, and the other half will get
heart-eyes smilies from the `smiley2` workload... as long as we also update
the `faces-back-end` Server definition to allow `face` to talk to `smiley2`!

```bash
kubectl edit -n faces server faces-back-end
kubectl apply -f k8s/03-linkerd-zero-trust/smiley-canary.yaml
```

Recall that that canary is happening deep in the mesh, well away from the
ingress controller that would often be the only way to do that.

# SUMMARY

We started with a wide-open application, completely locked down access to its
namespace, and then quickly enabled fairly minimal privileges to get back to a
working application -- all without changing the application at all, just using
features of Linkerd.
