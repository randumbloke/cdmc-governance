# Hub datasets (design §2.1, §5.2, §6.13.2): per region `dq_results_<env>_<region>` and
# `sdp_profiles_<env>_<region>`; in the home region `cdmc_report_<env>`. Every dataset has an
# explicit minimal access list and ignores later access changes; every later grant is one
# google_bigquery_dataset_access entry (design §6.15.2; VERIFY IN BUILD (VA-94)).

resource "google_bigquery_dataset" "dq_results" {
  for_each = toset(local.regions)

  project     = local.hub_project_id
  dataset_id  = "dq_results_${var.env}_${local.region_suffix[each.key]}"
  location    = each.key
  description = "Data quality scan results exported by every data project's scans in ${each.key} (design §3.6). Table scan_results is created by the first export."
  labels      = local.labels_file.hub_dataset

  delete_contents_on_destroy = false

  access {
    role          = "OWNER"
    user_by_email = local.governance_pipeline
  }

  lifecycle {
    ignore_changes = [access]
  }
}

resource "google_bigquery_dataset" "sdp_profiles" {
  for_each = toset(local.regions)

  project     = local.hub_project_id
  dataset_id  = "sdp_profiles_${var.env}_${local.region_suffix[each.key]}"
  location    = each.key
  description = "Sensitive Data Protection discovery profiles of the data projects in ${each.key} (design §5.3)."
  labels      = local.labels_file.hub_dataset

  delete_contents_on_destroy = false

  access {
    role          = "OWNER"
    user_by_email = local.governance_pipeline
  }

  lifecycle {
    ignore_changes = [access]
  }
}

resource "google_bigquery_dataset" "cdmc_report" {
  project     = local.hub_project_id
  dataset_id  = "cdmc_report_${var.env}"
  location    = local.home_region
  description = "CDMC findings and reporting (design §5.2). Holds resource names, principals and scores, not data values."
  labels      = local.labels_file.hub_dataset

  delete_contents_on_destroy = false

  access {
    role          = "OWNER"
    user_by_email = local.governance_pipeline
  }

  lifecycle {
    ignore_changes = [access]
  }
}

# --- Grants on the hub datasets (design §2.4.1, §2.4.5) ---------------------------------------

# Dataplex agent of each data project writes scan exports to the results dataset of the region
# (design §2.4.5, §3.6). VERIFY IN BUILD (VA-35): that scans in many projects can export to one
# table in the hub. VERIFY IN BUILD (VA-58): that these grants are sufficient.
resource "google_bigquery_dataset_access" "dq_results_dataplex_agent" {
  for_each = {
    for pair in setproduct(local.regions, keys(local.data_projects)) :
    "${pair[0]}/${pair[1]}" => { region = pair[0], project = pair[1] }
  }

  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.dq_results[each.value.region].dataset_id
  role          = "WRITER"
  user_by_email = local.dataplex_agent[each.value.project]
}

# SDP agent of each data project writes discovery profiles (design §2.4.5).
resource "google_bigquery_dataset_access" "sdp_profiles_dlp_agent" {
  for_each = {
    for pair in setproduct(local.regions, keys(local.data_projects)) :
    "${pair[0]}/${pair[1]}" => { region = pair[0], project = pair[1] }
  }

  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.sdp_profiles[each.value.region].dataset_id
  role          = "WRITER"
  user_by_email = local.dlp_agent[each.value.project]
}

# The evaluator reads scan results and the report dataset (design §2.4.1).
resource "google_bigquery_dataset_access" "dq_results_evaluator" {
  for_each = toset(local.regions)

  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.dq_results[each.key].dataset_id
  role          = "READER"
  user_by_email = local.evaluator_sa
}

resource "google_bigquery_dataset_access" "cdmc_report_evaluator" {
  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.cdmc_report.dataset_id
  role          = "READER"
  user_by_email = local.evaluator_sa
}

# The hub Pub/Sub agent writes the findings BigQuery subscription (design §2.4.5).
resource "google_bigquery_dataset_access" "cdmc_report_pubsub_agent" {
  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.cdmc_report.dataset_id
  role          = "WRITER"
  user_by_email = local.pubsub_agent
}

# Compliance reviewers read cdmc_report only (design §1.5.1, §5.2).
resource "google_bigquery_dataset_access" "cdmc_report_compliance" {
  for_each = toset(compact([var.compliance_reviewers_group]))

  project        = local.hub_project_id
  dataset_id     = google_bigquery_dataset.cdmc_report.dataset_id
  role           = "READER"
  group_by_email = each.key
}

# Phase 2 (design §2.4.1): the classifier reads profiles. Declared behind its flag.
resource "google_bigquery_dataset_access" "sdp_profiles_classifier" {
  for_each = var.components.classifier ? toset(local.regions) : toset([])

  project       = local.hub_project_id
  dataset_id    = google_bigquery_dataset.sdp_profiles[each.key].dataset_id
  role          = "READER"
  user_by_email = "classifier-${var.env}@${local.hub_project_id}.iam.gserviceaccount.com"
}
