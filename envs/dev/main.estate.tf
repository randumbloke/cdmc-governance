# Values from other repositories and this repository's tier stack (design §6.13.3). A missing
# file fails the plan, so this stack applied out of order changes nothing (design §6.14.1).

data "google_storage_bucket_object_content" "estate" {
  bucket = var.tf_state_bucket
  name   = "bootstrap/estate.json"
}

data "google_storage_bucket_object_content" "platform_tier" {
  bucket = var.tf_state_bucket
  name   = "outputs/dda-platform/tiers/${var.tier}/outputs.json"
}

data "google_storage_bucket_object_content" "platform_env" {
  bucket = var.tf_state_bucket
  name   = "outputs/dda-platform/${var.env}/outputs.json"
}

data "google_storage_bucket_object_content" "governance_tier" {
  bucket = var.tf_state_bucket
  name   = "outputs/cdmc-governance/tiers/${var.tier}/outputs.json"
}

locals {
  estate          = jsondecode(data.google_storage_bucket_object_content.estate.content)
  platform_tier   = jsondecode(data.google_storage_bucket_object_content.platform_tier.content)
  platform_env    = jsondecode(data.google_storage_bucket_object_content.platform_env.content)
  governance_tier = jsondecode(data.google_storage_bucket_object_content.governance_tier.content)
  labels_file     = jsondecode(file("${path.module}/../labels.json"))
  images          = { for k, v in jsondecode(file("${path.module}/../images.json")) : k => v if !startswith(k, "_") }

  hub_project_id     = local.platform_tier.hub_project_id
  hub_project_number = local.platform_tier.hub_project_number
  regions            = local.estate.regions
  home_region        = local.estate.regions[0]
  org_id             = local.estate.organization_id
  group_domain       = local.estate.group_domain
  cicd_project_id    = coalesce(local.estate.cicd_project_id, local.hub_project_id)
  single_deployer    = local.estate.single_deployer
  state_bucket       = local.governance_tier.hub_state_bucket

  region_suffix = { for r in local.regions : r => replace(r, "-", "_") }

  # Pipeline identities (design §2.4.4, §6.7.2).
  governance_pipeline = (
    local.single_deployer
    ? local.estate.deployer_service_accounts.apply
    : "tf-governance-${var.tier}@${local.cicd_project_id}.iam.gserviceaccount.com"
  )
  domain_pipeline = {
    for b in keys(var.domains) : b => (
      local.single_deployer
      ? local.estate.deployer_service_accounts.apply
      : "tf-${b}-${var.tier}@${local.cicd_project_id}.iam.gserviceaccount.com"
    )
  }

  # Hub runtime service account, created by the platform team (design §2.4.1, §6.17 asks).
  evaluator_sa = "evaluator-${var.env}@${local.hub_project_id}.iam.gserviceaccount.com"

  # Hub Pub/Sub service agent (BigQuery subscriptions, dead letters). The platform tier stack
  # publishes it; the computed form is the documented agent address (VA-101).
  pubsub_agent = try(
    local.platform_tier.service_agents["pubsub"],
    "service-${local.hub_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com",
  )

  # Data projects of this environment: the core data project and every analytics project
  # (key "core" or <business>, outputs_platform_env). A shared analytics project appears once.
  data_projects = {
    for p in distinct([for k, v in local.platform_env.projects : v.project_id]) : p => [
      for k, v in local.platform_env.projects : v if v.project_id == p
    ][0]
  }
  dataplex_agent = {
    for p, v in local.data_projects : p => try(
      v.service_agents["dataplex"],
      "service-${v.number}@gcp-sa-dataplex.iam.gserviceaccount.com",
    )
  }
  dlp_agent = {
    for p, v in local.data_projects : p => try(
      v.service_agents["dlp"],
      "service-${v.number}@dlp-api.iam.gserviceaccount.com",
    )
  }

  # Hub topics by logical name (design §2.5). The platform env outputs map logical names to
  # topic names; deployed names carry the environment suffix.
  topic_names = local.platform_env.topics
  topic = {
    for logical in ["kc-evaluator", "findings", "notifications", "sdp-profiles"] : logical => try(
      local.topic_names[logical],
      local.topic_names["${logical}-${var.env}"],
      "projects/${local.hub_project_id}/topics/${logical}-${var.env}",
    )
  }
  # Dead-letter topics `<topic>-dlq` (design §2.5.1), created by dda-platform. Null when the
  # platform outputs do not list one, so the subscription is created without dead lettering.
  dlq_topic = {
    for logical in ["kc-evaluator", "findings"] : logical => try(
      local.topic_names["${logical}-dlq"],
      local.topic_names["${logical}-${var.env}-dlq"],
      null,
    )
  }

  # Rollup queue, created by dda-platform (design §2.5.2, §6.13.2). The platform env outputs
  # schema has no queue field, so the name follows the logical-name rule (design §2.5).
  rollup_queue = "projects/${local.hub_project_id}/locations/${local.home_region}/queues/product-rollups-${var.env}"
}

check "hub_matches_estate" {
  assert {
    condition     = local.estate.hub_project_ids[var.tier] == local.platform_tier.hub_project_id
    error_message = "bootstrap/estate.json and the dda-platform tier outputs name different hub projects."
  }
}

check "env_declared" {
  assert {
    condition     = contains(local.estate.environments, var.env)
    error_message = "This environment is not declared in bootstrap/estate.json."
  }
}

check "images_by_digest" {
  assert {
    condition     = alltrue([for k, v in local.images : can(regex("@sha256:[0-9a-f]{64}$", v))])
    error_message = "Every image in envs/images.json must be referenced by @sha256: digest (design §6.10)."
  }
}
