Verify that Emissary-Ingress, Cert-manager, and Linkerd are installed as part of this demo. Please see the [README](README.md) for details on how to do that.

We'll first look at running [Polaris](https://polaris.docs.fairwinds.com/) as a standalone application. Download the binary from our [releases](https://github.com/FairwindsOps/polaris/releases) page and save it to a location in your `$PATH` or run it from wherever you've downloaded it.

Run
```
polaris dashboard --port 8080
```

Open a browser window to `localhost:8080`. You will see a GUI with a score and information on the compliance state of your cluster.

By default the report is run against a [set of checks](https://github.com/FairwindsOps/polaris/blob/master/examples/config.yaml) created from best practices as observed by Fairwinds, as well as frameworks from sources such as the [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF). For this demo we will want to use checks that are specifically concerned with enforcing the configurations that help us achieve zero trust.

Polaris allows you to create your own custom checks to run against your cluster. We've created a config file pre-populated with checks to that purpose:
- a check for making sure a workload has been added to the Linkerd mesh
- a check to make sure that any meshed workloads have corresponding `Server` objects for restricting access to those services
- a check to make sure that the default Linkerd cluster policy is not being overridden

All of these checks are JSONSchema written in YAML, meaning you can also write your own custom checks.

Now run
```
polaris --config polaris-config.yaml dashboard --port 8080
```

The dashboard will now be reporting on the specific checks related to Linkerd that we've added. We've exempted some common namespaces such as the control plane workloads and the Linkerd and Emissary-Ingress namespaces.

That's running Polaris as a standalone for quick audits. This can also be used in your CI/CD pipelines.

Now let's look at running Polaris as an Admission Controller. The `install-polaris-ac.sh` script will run a couple of simple Helm commands to install Polaris. It also points to a values file that contains similar custom checks as the config file we passed in the command above. The difference is we have commented out the `missingServer` check; because it's a multi-resource check, there's a dependency issue with defining the schema inline.

Verify the Helm chart installed correctly
```
kubectl get po -n polaris
```

You can view the settings of the Polaris validating webhook
```
kubectl get validatingwebhookconfiguration polaris-validate-webhook -oyaml
```

We've configured our checks with a severity of `warning`, so workloads that fail the check will not be rejected from the cluster, but we will see the event in the cluster event logs. We can also see the report of the failure in the dashboard still if we port-forward the service.

```
kubectl port-forward -n polaris svc/polaris-dashboard 8080:80
```

and access it in a browser using `localhost:8080` as before.


To see Polaris reject a workload:

- In the values.yaml file change
```
linkerdSidecarInjected: warning
```

to
```
linkerdSidecarInjected: danger
```

- rerun the `install-polaris-ac.sh` script.

- copy this sample nginx deployment to a local yaml file
```
kind: Deployment
metadata:
  name: nginx-1
  namespace: demo
  labels:
    app: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
      annotations:
        config.linkerd.io/default-inbound-policy: cluster-authenticated
        # linkerd.io/inject: enabled
    spec:
      containers:
      - name: nginx
        image: nginx:latest
```

- run `kubectl apply -f ${YOUR_YAML}`

You should see Polaris rejecting the workload like so
```
Error from server (
Polaris prevented this deployment due to configuration problems:
- Pod: Linkerd sidecar should be injected to enable mTLS
): error when creating "deployment.yaml": admission webhook "polaris.fairwinds.com" denied the request:
Polaris prevented this deployment due to configuration problems:
- Pod: Linkerd sidecar should be injected to enable mTLS
```