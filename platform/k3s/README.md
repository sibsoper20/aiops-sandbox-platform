# k3s foundation

## Safety

Review the selected k3s release and installation options before running the upstream installer. Keep the server token and kubeconfig out of Git.

## Install

Set a reviewed k3s release, then run the official installer:

```bash
export INSTALL_K3S_VERSION="<reviewed-k3s-version>"
curl -sfL https://get.k3s.io | sh -
```

Confirm the node:

```bash
sudo k3s kubectl get nodes
```

## Deploy the validation workload

```bash
sudo k3s kubectl apply -f platform/namespaces/namespaces.yaml
sudo k3s kubectl apply -f platform/k3s/test-workload.yaml
sudo k3s kubectl -n demo rollout status deployment/foundation-test
```

Map `aiops-demo.local` to the UM780 LAN address in the client hosts file, then open `http://aiops-demo.local`.

## Completion tests

1. Confirm the browser returns the test page.
2. Delete the pod and confirm the Deployment replaces it.
3. Reboot the host and confirm k3s, ingress, and the test workload return.
4. Record results in `tests/foundation-validation.md`.

## Remove the test workload

```bash
sudo k3s kubectl delete -f platform/k3s/test-workload.yaml
```

## Uninstall k3s

Use the k3s-generated uninstall script only when intentionally removing the cluster:

```bash
sudo /usr/local/bin/k3s-uninstall.sh
```

The validation workload uses a mutable test image for initial convenience. Pin it to a reviewed digest before treating the environment as reproducible.
