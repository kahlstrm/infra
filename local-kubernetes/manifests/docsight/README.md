# DOCSight

One replica in Talos's monitoring namespace polls the Sagemcom modem every 60
seconds. SQLite history uses a 2 GiB local-storage PVC with seven-day retention.
Prometheus scrapes through a ServiceMonitor and retains its existing history.
The local volume binds the workload to its storage node; this is not an HA setup.

The UI is available at **https://docsight.kube.kalski.xyz** through the existing
private Traefik ingress class, with a certificate from the letsencrypt issuer.
Log in with the configured administrator password. The same app service exposes
`/metrics`, protected by a metrics-scoped bearer token for Prometheus.

For direct troubleshooting access:

```sh
kubectl --context admin@klusse -n monitoring port-forward deployment/docsight 8765:8765
```

The current Flannel CNI does not enforce NetworkPolicy. Internal cluster clients
can reach the app service; administrator authentication protects management
routes. The included policy declares ingress from Prometheus and private Traefik
for an enforcing CNI. This deployment creates no public ingress.

## Provision and activate

1. Merge the DOCSight image-workflow PR and confirm a successful main build.
   Anonymous GHCR pulls were verified for the initial pinned digest. Keep the
   package public; no registry secret is needed.
2. Add `docsight.admin_password` and `docsight.scrape_token` to the existing
   local-networking Google Secret Manager blob using its `just edit` workflow.
   Use a strong random administrator password and a separate random scrape token
   beginning with `dsk_`, at least 48 characters long. The existing
   `cable_modem.username` and `cable_modem.password` provide modem access.
3. Review and apply the local-talos Terraform plan to create docsight-credentials
   in monitoring. Secrets are managed through Terraform, not kubectl.
4. Verify the digest in kustomization.yaml is published and pullable. Merge the
   infra PR; the existing apps root application discovers docsight.yaml and
   Argo CD automatically syncs it.
5. Check the pod is ready, Prometheus's docsight target is up, and uptime and
   DOCSIS status metrics are present. No modem reboot is required.

Kustomize updates the scripts ConfigMap name when its contents change, triggering
a rollout. The PVC is protected from Argo prune/application deletion. Recreate
strategy avoids simultaneous writers; upgrades have a brief monitoring gap.

## Updates

The fork tests and builds images on main changes and rebuilds every Monday at
05:41 UTC with fresh OS packages. `main` is the discovery tag; Kubernetes uses
its pinned digest. Install/authorize the Renovate GitHub app for kahlstrm/infra
if it is not already installed. renovate.json scopes updates to this image only
and leaves merge approval manual. Merging a digest update deploys through Argo CD.

Review upstream changes and merge them into the DOCSight fork separately.
Weekly image builds do not update application source or pinned Python packages.

Changing a secret does not restart the pod automatically. After applying a
credential rotation through Terraform, restart the deployment so bootstrap can
update the managed token hash:

```sh
kubectl --context admin@klusse -n monitoring rollout restart deployment/docsight
```

For rollback, revert the image-digest commit. Preserve a copy of the data volume
before upgrades that migrate SQLite; an older image may require its matching
pre-upgrade database. Reverting an image does not undo database migrations.

## Validation

```sh
kubectl kustomize local-kubernetes/manifests/docsight > /tmp/docsight.yaml
kubectl --context admin@klusse apply --dry-run=server -f /tmp/docsight.yaml
python local-kubernetes/tests/docsight/check_rules.py
DOCSIGHT_IMAGE=ghcr.io/kahlstrm/docsight@sha256:ACTUAL_DIGEST \
  python local-kubernetes/tests/docsight/smoke.py
```

The rule tests use PyYAML and promtool. The smoke test uses Docker and synthetic
credentials, verifies token rotation, UI login and metrics-only access, and removes its
containers and volume when finished.
