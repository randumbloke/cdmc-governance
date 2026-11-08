# Hub state bucket `<hub>-dda-state` (design §2.3.2): the trust anchor for domain state, the
# infoType rule table, published products, lineage manifests and declared bindings. Write
# access is split by managed folder; readers hold bucket-level objectViewer.

locals {
  state_bucket_name = "${local.hub_project_id}-dda-state"

  # Managed folders and their single writer (design §2.3.2 table; §6.7.2 single deployer).
  governance_folders = {
    "domains/"        = local.governance_pipeline
    "classification/" = local.governance_pipeline
  }
  domain_folders = merge([
    for pair in setproduct(local.tier_envs, var.domain_businesses) : {
      for kind in ["products", "lineage", "bindings"] :
      "${kind}/${pair[0]}/${pair[1]}-${pair[0]}/" => local.domain_pipeline[pair[1]]
    }
  ]...)
  managed_folders = merge(local.governance_folders, local.domain_folders)
}

resource "google_storage_bucket" "state" {
  project                     = local.hub_project_id
  name                        = local.state_bucket_name
  location                    = local.home_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.labels_file.hub_bucket

  versioning {
    enabled = true
  }

  # Keep recent history of every published file (same rule as the Terraform state bucket,
  # design §6.16.3).
  lifecycle_rule {
    condition {
      num_newer_versions         = 20
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
}

# Object-creation audit logs (design §2.3.2): the Eventarc trigger on products/ and lineage/
# (envs/<env>/main.events.tf) is a Cloud Audit Logs trigger, which needs Data Write logs for
# Cloud Storage in the hub; the evaluator trusts the uploader identity in the audit entry.
resource "google_project_iam_audit_config" "hub_storage" {
  project = local.hub_project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_storage_managed_folder" "folder" {
  for_each = local.managed_folders

  bucket        = google_storage_bucket.state.name
  name          = each.key
  force_destroy = false
}

# Design §2.3.2 grants roles/storage.objectCreator. Under single_deployer the writer is
# tf-deployer, which also holds roles/storage.admin on the hub (union of tf-governance grants,
# §2.4.4, §6.7.2), so re-publishing (overwriting) a file works. With split accounts,
# objectCreator alone cannot overwrite an existing object (no storage.objects.delete):
# VERIFY IN BUILD (AT-05, AT-06) before single_deployer is turned off.
resource "google_storage_managed_folder_iam_member" "writer" {
  for_each = local.managed_folders

  bucket         = google_storage_bucket.state.name
  managed_folder = google_storage_managed_folder.folder[each.key].name
  role           = "roles/storage.objectCreator"
  member         = "serviceAccount:${each.value}"
}

# Readers (design §2.4.1): the evaluator reads the whole bucket.
resource "google_storage_bucket_iam_member" "evaluator_reader" {
  for_each = local.evaluator_sa

  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${each.value}"
}

# Phase 2 (design §6.17): the classifier reads classification/ and domains/.
resource "google_storage_managed_folder_iam_member" "classifier_reader" {
  for_each = {
    for pair in setproduct(local.tier_envs, keys(local.governance_folders)) :
    "${pair[0]}/${pair[1]}" => { env = pair[0], folder = pair[1] } if var.classifier_enabled
  }

  bucket         = google_storage_bucket.state.name
  managed_folder = google_storage_managed_folder.folder[each.value.folder].name
  role           = "roles/storage.objectViewer"
  member         = "serviceAccount:${local.classifier_sa[each.value.env]}"
}

# The infoType rule table (design §5.3.3), published on every apply. The classifier loads it by
# `version` and records `rule_version` on every level it sets.
locals {
  infotype_rules_source = file("${path.module}/../../classification/infotype_rules.yaml")
  infotype_rules        = yamldecode(local.infotype_rules_source)
}

resource "google_storage_bucket_object" "infotype_rules" {
  bucket       = google_storage_bucket.state.name
  name         = "classification/infotype_rules.yaml"
  content      = local.infotype_rules_source
  content_type = "application/yaml"
  metadata = {
    rule-version = tostring(local.infotype_rules.version)
  }

  depends_on = [google_storage_managed_folder.folder]
}

# A copy per version, so the version a level records can always be read back.
resource "google_storage_bucket_object" "infotype_rules_versioned" {
  bucket       = google_storage_bucket.state.name
  name         = "classification/infotype_rules.v${local.infotype_rules.version}.yaml"
  content      = local.infotype_rules_source
  content_type = "application/yaml"

  depends_on = [google_storage_managed_folder.folder]
}
