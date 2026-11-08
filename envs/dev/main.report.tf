# cdmc_report tables and views (design §5.2). Phase 1 creates the tables the evaluator and the
# findings subscription write, and the three reporting views. sharing_agreements,
# classification_decisions and expiring_access belong to later phases (gate, classifier,
# reconciler) and are created with them.

locals {
  seven_years_ms = 7 * 365 * 24 * 60 * 60 * 1000
  days_400_ms    = 400 * 24 * 60 * 60 * 1000
  report_ref     = "${local.hub_project_id}.${google_bigquery_dataset.cdmc_report.dataset_id}"

  events_schema = [
    { name = "finding_id", type = "STRING", mode = "REQUIRED", description = "SHA-256 of asset, check, triggering event or job ID, and evaluator version." },
    { name = "environment", type = "STRING", mode = "NULLABLE", description = "dev, test, uat or prod." },
    { name = "control", type = "STRING", mode = "NULLABLE", description = "C2, C3, C5, C6, C7, C8, C12 or C14." },
    { name = "check", type = "STRING", mode = "NULLABLE", description = "The check, for example C12.coverage." },
    { name = "asset", type = "STRING", mode = "NULLABLE", description = "Full resource name; a column is <table>#<column>." },
    { name = "asset_type", type = "STRING", mode = "NULLABLE", description = "DATASET, TABLE, COLUMN, DATA_PRODUCT, DATA_DOMAIN, BINDING, MEMBERSHIP." },
    { name = "domain", type = "STRING", mode = "NULLABLE", description = "Owning domain." },
    { name = "product", type = "STRING", mode = "NULLABLE", description = "Data product, where applicable." },
    { name = "detected_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Publication time." },
    {
      name = "evaluation", type = "RECORD", mode = "NULLABLE", description = "Authoritative evaluation (D-01)."
      fields = [
        { name = "status", type = "STRING", mode = "NULLABLE", description = "PASS, FAIL, PENDING, NOT_EVALUATED." },
        { name = "measured_value", type = "FLOAT", mode = "NULLABLE", description = "Measured value, where the check compares one." },
        { name = "threshold", type = "FLOAT", mode = "NULLABLE", description = "Threshold, where the check compares one." },
        { name = "detail", type = var.findings_detail_type, mode = "NULLABLE", description = "Check-specific evidence. VERIFY IN BUILD (VA-61)." },
        { name = "evaluator_version", type = "STRING", mode = "NULLABLE", description = "Module name and version." },
        { name = "evaluated_at", type = "TIMESTAMP", mode = "NULLABLE", description = "Evaluation time." },
        { name = "source_ref", type = "STRING", mode = "NULLABLE", description = "Resource name of the evidence." },
        { name = "trigger", type = "STRING", mode = "NULLABLE", description = "EVENT, SWEEP or RECONCILE." },
      ]
    },
    {
      name = "route", type = "RECORD", mode = "NULLABLE", description = "Groups resolved by the C2 rules at evaluation time."
      fields = [
        { name = "owner", type = "STRING", mode = "NULLABLE", description = "Effective owner group." },
        { name = "steward", type = "STRING", mode = "NULLABLE", description = "Effective steward group." },
        { name = "escalation", type = "STRING", mode = "NULLABLE", description = "Escalation group." },
      ]
    },
  ]
}

resource "google_bigquery_table" "events" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "events"
  description         = "Every finding, pass or fail, written by the findings BigQuery subscription (design §5.2; P5-1)."
  deletion_protection = var.deletion_protection
  labels              = local.labels_file.hub_dataset

  time_partitioning {
    type          = "DAY"
    field         = "detected_at"
    expiration_ms = local.seven_years_ms
  }

  # Design §5.2 also clusters by evaluation.status; BigQuery clusters on top-level columns only,
  # so the nested status is not a clustering column.
  clustering = ["control", "domain"]

  schema = jsonencode(local.events_schema)
}

resource "google_bigquery_table" "narratives" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "narratives"
  description         = "Advisory narratives joined to events by finding_id (design §5.2; P5-2). Written by the explainer, a later phase; created now so the views resolve."
  deletion_protection = var.deletion_protection
  labels              = local.labels_file.hub_dataset

  time_partitioning {
    type          = "DAY"
    field         = "created_at"
    expiration_ms = local.seven_years_ms
  }

  schema = jsonencode([
    { name = "finding_id", type = "STRING", mode = "REQUIRED" },
    { name = "summary", type = "STRING", mode = "NULLABLE" },
    { name = "model", type = "STRING", mode = "NULLABLE" },
    { name = "prompt_version", type = "STRING", mode = "NULLABLE" },
    { name = "authoritative", type = "BOOLEAN", mode = "NULLABLE", description = "Always false." },
    { name = "created_at", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

resource "google_bigquery_table" "data_assets" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "data_assets"
  description         = "Daily asset snapshot written by the evaluator sweep (design §5.2)."
  deletion_protection = var.deletion_protection
  labels              = local.labels_file.hub_dataset

  time_partitioning {
    type          = "DAY"
    field         = "snapshot_date"
    expiration_ms = local.days_400_ms
  }

  schema = jsonencode([
    { name = "snapshot_date", type = "DATE", mode = "REQUIRED" },
    { name = "asset", type = "STRING", mode = "REQUIRED" },
    { name = "asset_type", type = "STRING", mode = "NULLABLE" },
    { name = "project", type = "STRING", mode = "NULLABLE" },
    { name = "dataset", type = "STRING", mode = "NULLABLE" },
    { name = "domain", type = "STRING", mode = "NULLABLE" },
    { name = "subdomain", type = "STRING", mode = "NULLABLE" },
    { name = "product", type = "STRING", mode = "NULLABLE" },
    { name = "classification_level", type = "STRING", mode = "NULLABLE" },
    { name = "designation", type = "STRING", mode = "NULLABLE" },
    { name = "is_provisioning_point", type = "BOOLEAN", mode = "NULLABLE" },
    { name = "effective_owner", type = "STRING", mode = "NULLABLE" },
    { name = "effective_steward", type = "STRING", mode = "NULLABLE" },
  ])
}

# Design §2.4.1 grants evaluator-<env> roles/bigquery.dataEditor on table data_assets only, but
# §6.15.3 forbids google_bigquery_table_iam_* and §6.15.2 allows dataset-level entries only.
# No grant is made here: the sweep cannot write data_assets until the design settles the
# conflict (listed in the README). Phase 1 controls (C12, C14) do not read data_assets.

resource "google_bigquery_table" "findings_dedup" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "findings_dedup"
  description         = "One row per finding_id; absorbs at-least-once delivery (design §5.2)."
  deletion_protection = var.deletion_protection

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/sql/findings_dedup.sql", { report = local.report_ref })
  }

  depends_on = [google_bigquery_table.events]
}

resource "google_bigquery_table" "last_run_findings_summary" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "last_run_findings_summary"
  description         = "Latest finding per asset and check, with pass and fail ratios by domain and control (design §5.2)."
  deletion_protection = var.deletion_protection

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/sql/last_run_findings_summary.sql", { report = local.report_ref })
  }

  depends_on = [google_bigquery_table.findings_dedup]
}

resource "google_bigquery_table" "coverage_daily" {
  project             = local.hub_project_id
  dataset_id          = google_bigquery_dataset.cdmc_report.dataset_id
  table_id            = "coverage_daily"
  description         = "Assets evaluated by the sweep divided by assets in scope, per control and day (design §5.2)."
  deletion_protection = var.deletion_protection

  view {
    use_legacy_sql = false
    query          = templatefile("${path.module}/sql/coverage_daily.sql", { report = local.report_ref, time_zone = var.scheduler_time_zone })
  }

  depends_on = [google_bigquery_table.findings_dedup, google_bigquery_table.data_assets]
}
