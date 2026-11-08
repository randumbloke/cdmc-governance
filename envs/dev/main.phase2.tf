# Later-phase resources that the §6.17 component flags switch on. Phase 1 sets every flag below
# to false, so nothing here is created; the declarations exist so that a later phase changes only
# <env>.tfvars (change design, goal 3). The classifier, gate, reconciler and explainer services
# are not declared: their code is not written in phase 1 (brief; change design, non-goals).

# policy_tags (design §5.3.2, §6.17; decision P6-36): one taxonomy per domain, environment and
# region, with the two tags CONFIDENTIAL and RESTRICTED.
locals {
  taxonomies = {
    for pair in setproduct(keys(var.domains), local.regions) :
    "${pair[0]}/${pair[1]}" => { business = pair[0], region = pair[1] } if var.components.policy_tags
  }
  policy_tags = merge([
    for k, t in local.taxonomies : {
      for level in ["CONFIDENTIAL", "RESTRICTED"] : "${k}/${level}" => { taxonomy = k, level = level }
    }
  ]...)
}

resource "google_data_catalog_taxonomy" "domain" {
  for_each = local.taxonomies

  project                = local.hub_project_id
  region                 = each.value.region
  display_name           = "dda-${each.value.business}-${var.env}-${each.value.region}"
  description            = "Column policy tags of ${local.domain_id[each.value.business]} in ${each.value.region} (design §5.3.2)."
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "level" {
  for_each = local.policy_tags

  taxonomy     = google_data_catalog_taxonomy.domain[each.value.taxonomy].id
  display_name = each.value.level
  description  = "Columns classified ${each.value.level}."
}

# steward_inbox (design §5.3.4): bucket with per-domain requests/ and approvals/ managed folders.
# VERIFY IN BUILD (VA-40): separate IAM per managed folder in one bucket.
resource "google_storage_bucket" "steward_inbox" {
  count = var.components.steward_inbox ? 1 : 0

  project                     = local.hub_project_id
  name                        = "${local.hub_project_id}-dda-classification-inbox-${var.env}"
  location                    = local.home_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels_file.hub_bucket

  versioning {
    enabled = true
  }

  retention_policy {
    retention_period = 7 * 365 * 24 * 60 * 60
  }
}

locals {
  inbox_folders = merge(
    {
      for b, d in var.domains : "requests/${local.domain_id[b]}/" => "group:${local.stewards_group[b]}"
      if var.components.steward_inbox
    },
    {
      for b, d in var.domains : "approvals/${local.domain_id[b]}/" => "group:${local.owners_group[b]}"
      if var.components.steward_inbox
    },
  )
}

resource "google_storage_managed_folder" "inbox" {
  for_each = local.inbox_folders

  bucket = google_storage_bucket.steward_inbox[0].name
  name   = each.key
}

resource "google_storage_managed_folder_iam_member" "inbox_writer" {
  for_each = local.inbox_folders

  bucket         = google_storage_bucket.steward_inbox[0].name
  managed_folder = google_storage_managed_folder.inbox[each.key].name
  role           = "roles/storage.objectCreator"
  member         = each.value
}
