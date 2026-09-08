# DOCSight

Internal UI: **https://docsight.kube.kalski.xyz**, using the configured administrator password.

Runs in the `docsight` namespace with a 2 GiB local PVC and seven-day history.
Prometheus scrapes every 60 seconds using a metrics-scoped token. The local volume
pins the single replica to its storage node; updates briefly interrupt collection.
Flannel does not enforce NetworkPolicy, so service access relies on application authentication.

## Activate

1. Merge `kahlstrm/docsight#4` and confirm its main image build succeeds.
2. Run `just edit` in `local-networking` and add `docsight.admin_password` and
   `docsight.scrape_token`. Use separate random values; the token must start with
   `dsk_` and be at least 48 characters. Existing `cable_modem` credentials are reused.
3. Review and apply the `local-talos` Terraform plan to provision the namespace and
   credentials. Manage secrets through Terraform, not kubectl.
4. Merge the infra PR. Argo CD discovers and syncs the application automatically.
5. Check pod readiness, UI login, and Prometheus's DOCSight target and metrics.

The GHCR package must remain public. Authorize Renovate for `kahlstrm/infra` to
receive image updates.

## Maintain

Renovate proposes digest updates; merging them deploys through Argo CD. The fork
builds on main image changes, version tags, and manual dispatch. Merge upstream
source changes separately.

After rotating credentials through Terraform:

```sh
kubectl --context admin@klusse -n docsight rollout restart deployment/docsight
```

Rollback by reverting the digest commit. Back up SQLite before schema-changing
upgrades; reverting the image does not revert the database. Argo pruning preserves the PVC.

## Validate

From the repository root, with kubectl, Python/PyYAML, promtool, and Docker available:

```sh
kubectl kustomize local-kubernetes/manifests/docsight > /tmp/docsight.yaml
kubectl --context admin@klusse apply --dry-run=server -f /tmp/docsight.yaml
python local-kubernetes/tests/docsight/check_rules.py
DOCSIGHT_IMAGE=ghcr.io/kahlstrm/docsight@sha256:ACTUAL_DIGEST \
  python local-kubernetes/tests/docsight/smoke.py
```
