# cdmc-governance

Hub configuration of the Decentralised Data Architecture (DDA) on Google Cloud: the governance
artefacts that every environment of a hub shares, and per environment the data domains, hub
datasets, discovery, and the control evaluator with its event wiring. Design references are to
`docs/design/dda_technical_design.md` in the specification repository (`cdmc_kc`); shared
names, paths and file shapes are in `cdmc_kc/deployment/contracts/`.

This is the phase 1 draft (change `mvp-phase-1-build`, OD-3): code first, then deploy and check.
Phase 1 is `dev` only, with C12 and C14 (design §6.17).

## Layout

```text
aspect_types/cdmc_aspect_types.yaml   the five custom aspect type templates (§5.11); verbatim copy of
                                      kc-control-plane src/cdmc_common/aspect_types/ (commit f752247)
classification/infotype_rules.yaml    the infoType rule table (§5.3.3)
glossary/glossary.yaml                governance glossary: four categories of request-label terms (§4.2.1)
schemas/infotype_rules.schema.json    schema of the rule table (CI)
tiers/nonprod/                        tier stack (§6.13.1): aspect types and their IAM, glossary, inspection
                                      template per region, hub state bucket, managed folders and their IAM,
                                      rule table object; writes outputs/cdmc-governance/tiers/nonprod/outputs.json
envs/labels.json                      labels by resource type (§1.6)
envs/images.json                      control plane images by digest (§6.10)
envs/dev/                             environment stack: domains and subdomains (dda-platform domain shim),
                                      domains/dev.json, hub datasets and their grants, cdmc_report tables and
                                      views, discovery configurations, evaluator service and sweep job,
                                      feed-evaluator push subscription, findings BigQuery subscription,
                                      Eventarc triggers on products/ and lineage/, Cloud Scheduler sweep;
                                      later-phase resources behind §6.17 flags; writes
                                      outputs/cdmc-governance/dev/outputs.json
  sql/                                reporting view queries (§5.2)
  tests/, ../../tiers/nonprod/tests/  offline `terraform test` plans with mocked providers
scripts/ci_checks.py                  repository checks of §6.3 (root-module comparison, projectReaders,
                                      IAM ownership, dataset access, local execution, image digests,
                                      lock files, workflows, rule table schema, aspect indexes)
tests/test_ci_checks.py               pytest golden tests of the check script
.github/workflows/ci.yml              ci-checks (§6.3)
```

Each root module has `backend.tf` (empty `gcs` backend), `state.config`, `<tier|env>.tfvars`,
`providers.tf`, `variables.tf`, `outputs.tf`, `main.<concern>.tf` and a committed
`.terraform.lock.hcl` (linux_amd64, darwin_arm64, darwin_amd64).

## Inputs and outputs

No value from another repository is repeated in `.tfvars`. Each stack reads, with
`google_storage_bucket_object_content` from `tfstate-pltfrm-ngnrng`, and fails its plan if a file
is missing (§6.13.3):

| Stack | Reads | Writes |
|---|---|---|
| `tiers/nonprod` | `bootstrap/estate.json`, `outputs/dda-platform/tiers/nonprod/outputs.json` | `outputs/cdmc-governance/tiers/nonprod/outputs.json`; hub `classification/infotype_rules.yaml` (and `.v<version>.yaml`) |
| `envs/dev` | the two above, `outputs/dda-platform/dev/outputs.json`, `outputs/cdmc-governance/tiers/nonprod/outputs.json` | `outputs/cdmc-governance/dev/outputs.json`; hub `domains/dev.json` |

`hub_datasets` values are dataset IDs in the hub project (`dq_results_dev_australia_southeast1`);
domain scans export to table `scan_results` in that dataset, which the first export creates.

## Checks

```sh
terraform fmt -check -recursive
(cd tiers/nonprod && terraform init -backend=false && terraform validate && terraform test)
(cd envs/dev && terraform init -backend=false && terraform validate && terraform test)
uv sync && uv run python scripts/ci_checks.py && uv run pytest -q
```

`envs/dev` sources the domain module from
`git::https://github.com/randumbloke/dda-platform.git//modules/data_domain_shim/domain?ref=main`,
so its `init` works only once `dda-platform` has pushed that module. Until then, validate against a
local clone by pointing `source` at `../../../dda-platform/modules/data_domain_shim/domain`
temporarily (do not commit it).

CI (`.github/workflows/ci.yml`) adds tflint with the Google ruleset, a Trivy misconfiguration
scan and a gitleaks secret scan; these tools were not run locally for the draft.

## Deployment

Applied by Cloud Build on merge to `main`, as `tf-deployer` (`single_deployer = true`, §6.7.2):
`tiers/nonprod/`, then `envs/dev/` (§6.13.1, §6.14), each with
`terraform init -backend-config=state.config -lockfile=readonly` and
`-var-file=<tier|env>.tfvars`; a failed stack is retried once (§6.14.3). Pull requests are
planned as `tf-deployer-plan`. Repository order: after `dda-platform` and the first
`kc-control-plane` image build, before the domain repositories (§6.14.1).

Before the first `envs/dev` apply, replace the placeholder digest in `envs/images.json` with the
digest that the `kc-control-plane` image build published in `outputs/kc-control-plane/images.json`.

## Expectations on other repositories

- `dda-platform` tier outputs: `service_agents.pubsub` (falls back to the computed agent email).
- `dda-platform` dev outputs: `projects.core` and `projects.<business>`; `service_agents.dataplex`,
  `.dlp` per project (fallback: computed emails); `topics` keyed by logical name
  (`kc-evaluator`, `findings`, `notifications`, `sdp-profiles`, and `<topic>-dlq` for dead-letter
  topics; a missing `-dlq` key creates the subscription without dead lettering);
  `domain_service_accounts.<business>.{ingest,analytics}`. The rollup queue is assumed to be
  `projects/<hub>/locations/<home region>/queues/product-rollups-dev` (no queue field in the
  contract). Publisher grants for the Pub/Sub agent on `-dlq` topics are dda-platform's.
- The domain shim's `policy_member` output is a string principal.
- The evaluator image (kc-control-plane, commit 2ca1284) reads `cdmc_common.config.Settings`
  from environment variables, all set in `envs/dev/main.evaluator.tf`: `DDA_ENV`,
  `HUB_PROJECT_ID`, `REGION`, `CICD_PROJECT_ID`, `HUB_STATE_BUCKET`, `FINDINGS_TOPIC`,
  `DQ_RESULTS_TABLE`, `ROLLUP_QUEUE`, `ROLLUP_HANDLER_URL`, `ROLLUP_INVOKER_SA`,
  `ROLLUP_WINDOW_SECONDS`, `DATA_PROJECTS`, `SINGLE_DEPLOYER`, `SCHEDULER_TIME_ZONE`,
  `EVALUATOR_MODULES`. Routes: `/events/kc` (feed-evaluator push), `/events/state` (Eventarc),
  `/tasks/rollup` (Cloud Tasks). The sweep job runs the same image with command
  `evaluator-sweep`, 20 tasks.

## Open points (design conflicts found while drafting)

1. **`data_assets` grant.** §2.4.1 grants `evaluator-<env>` `roles/bigquery.dataEditor` on table
   `cdmc_report.data_assets`, but §6.15.3 forbids `google_bigquery_table_iam_*` and §6.15.2 allows
   dataset entries only. No grant is made, so the sweep cannot write `data_assets` (not needed
   by C12 or C14).
2. **Managed folder writers.** §2.3.2 grants `roles/storage.objectCreator`, which cannot overwrite
   a re-published file. Works under `single_deployer` (`tf-deployer` has `storage.admin` on the hub).
3. **`events` clustering.** §5.2 clusters by `evaluation.status`; BigQuery clusters on top-level
   columns only, so `events` clusters by `control`, `domain`.
4. **Subdomain IDs.** Domain IDs share one namespace per project and location, so subdomains are
   `<domain>-<stage>` (`customer-dev-curated`); the stage stays the key in every file.
5. **Entry types.** The design names none; `entry_types` is published empty.
6. **`cdmc_findings`.** Contracts §2 lists a hub dataset `cdmc_findings`; the design sends findings
   to `cdmc_report.events` and names no such dataset, so none is created.
7. **Storage audit configuration.** The tier stack sets Data Write audit logs for Cloud Storage
   on the hub (needed by the Eventarc audit-log trigger); `google_project_iam_audit_config` is
   authoritative for that service's audit configuration on the hub.

## VERIFY IN BUILD markers

| ID | Where | What |
|---|---|---|
| VA-09 | `envs/dev/main.events.tf` | feed-evaluator payload shape |
| VA-12 | `envs/dev/main.domains.tf` | `policy_member` can be granted like any principal |
| VA-17 | `envs/dev/main.domains.tf` | domains regional (home region) |
| VA-35 | `envs/dev/main.datasets.tf` | many projects' scans export to one hub table |
| VA-36, VA-37 | `envs/dev/main.discovery.tf` | profile aspect on entries; export columns |
| VA-39 | `tiers/nonprod/main.dlp.tf`, `envs/dev/main.discovery.tf`, `variables.tf` | discovery config uses the hub template |
| VA-40 | `envs/dev/main.phase2.tf` | inbox managed folder IAM (phase 2) |
| VA-42, VA-76 | `tiers/nonprod/main.aspect_types.tf` | aspect writer permissions |
| VA-48, VA-87 | `envs/dev/main.domains.tf` | domain grants reach bound resources; parent vs subdomain |
| VA-52 | `envs/dev/main.evaluator.tf` | internal ingress accepts Pub/Sub, Eventarc, Scheduler, Tasks |
| VA-58 | `envs/dev/main.datasets.tf` | agent grants sufficient |
| VA-59 | `envs/dev/main.discovery.tf`, `variables.tf` | export and config locations |
| VA-61 | `envs/dev/main.report.tf`, `main.events.tf`, `variables.tf` | Avro detail into a JSON column |
| VA-62, VA-96 | `envs/dev/main.domains.tf` | domain patch and IAM; operation polling |
| VA-93, VA-101 | `envs/dev/main.estate.tf` | agents exist; computed agent emails |
| VA-94 | `envs/dev/main.datasets.tf` | dataset access pattern keeps entries |
| VA-99 | `envs/dev/main.events.tf` | `ddaSubscriptionAdmin` sufficient |
| AT-05, AT-06 | `tiers/nonprod/main.state_bucket.tf` | objectCreator cannot overwrite (split accounts) |
| no VA ID | `envs/dev/main.events.tf` | Eventarc `match-path-pattern` on Storage audit `resourceName`; trigger location |
| no VA ID | `envs/images.json`, `envs/dev/main.evaluator.tf` | placeholder digest until the first image build; `evaluator-sweep` on the image PATH |
| no VA ID | `.github/workflows/ci.yml`, `.tflint.hcl` | action SHA and tool versions |
