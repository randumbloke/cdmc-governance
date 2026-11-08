# Values from other repositories (design §6.13.3). A missing file fails the plan, so this stack
# applied before bootstrap or the dda-platform tier stack changes nothing.

data "google_storage_bucket_object_content" "estate" {
  bucket = var.tf_state_bucket
  name   = "bootstrap/estate.json"
}

data "google_storage_bucket_object_content" "platform_tier" {
  bucket = var.tf_state_bucket
  name   = "outputs/dda-platform/tiers/${var.tier}/outputs.json"
}

locals {
  estate        = jsondecode(data.google_storage_bucket_object_content.estate.content)
  platform_tier = jsondecode(data.google_storage_bucket_object_content.platform_tier.content)
  labels_file   = jsondecode(file("${path.module}/../../envs/labels.json"))

  hub_project_id     = local.platform_tier.hub_project_id
  hub_project_number = local.platform_tier.hub_project_number
  regions            = local.estate.regions
  home_region        = local.estate.regions[0]
  org_id             = local.estate.organization_id
  group_domain       = local.estate.group_domain
  cicd_project_id    = coalesce(local.estate.cicd_project_id, local.hub_project_id)
  single_deployer    = local.estate.single_deployer

  # Environments served by this tier's hub (design §2.1, §6.2).
  tier_of_env = { dev = "nonprod", test = "nonprod", uat = "prod", prod = "prod" }
  tier_envs   = [for e in local.estate.environments : e if local.tier_of_env[e] == var.tier]

  # Pipeline identities (design §2.4.4, §6.7.2).
  governance_pipeline = (
    local.single_deployer
    ? local.estate.deployer_service_accounts.apply
    : "tf-governance-${var.tier}@${local.cicd_project_id}.iam.gserviceaccount.com"
  )
  domain_pipeline = {
    for b in var.domain_businesses : b => (
      local.single_deployer
      ? local.estate.deployer_service_accounts.apply
      : "tf-${b}-${var.tier}@${local.cicd_project_id}.iam.gserviceaccount.com"
    )
  }

  # Hub runtime service accounts, created by the platform team (design §2.4, §6.17 asks).
  evaluator_sa  = { for e in local.tier_envs : e => "evaluator-${e}@${local.hub_project_id}.iam.gserviceaccount.com" }
  classifier_sa = { for e in local.tier_envs : e => "classifier-${e}@${local.hub_project_id}.iam.gserviceaccount.com" }
}

check "hub_matches_estate" {
  assert {
    condition     = local.estate.hub_project_ids[var.tier] == local.platform_tier.hub_project_id
    error_message = "bootstrap/estate.json and the dda-platform tier outputs name different hub projects."
  }
}
