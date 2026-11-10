# Metadata feeds, one per subscriber, filtered to the aspect types it consumes (design §2.5;
# RV-A4; OD-8 / MB-14). Created in cdmc-governance after tiers/<tier>/ has created the custom
# aspect types (cdmc-classification) that feed-evaluator filters on. Scope: this environment's
# data projects, listed (not organizationLevel), so each environment's feeds see only its own
# projects.
#
# VERIFY IN BUILD (VA-59): the feed location (default: home region).
# VERIFY IN BUILD (VA-09): event payload shape; the aspect type and project name forms below.

locals {
  feed_location = coalesce(var.metadata_feed_location, local.home_region)
  # The API stores aspect type names with project numbers, so the config uses that form or every
  # plan shows a diff (AT-06). 655216118709 is the project number of dataplex-types.
  system_aspect = "projects/655216118709/locations/global/aspectTypes"
  custom_aspect = "projects/${local.hub_project_number}/locations/global/aspectTypes"

  feed_scope_projects = [for p in sort(keys(local.data_projects)) : "projects/${local.data_projects[p].number}"]

  feeds = merge(
    {
      "feed-evaluator" = {
        topic = "kc-evaluator"
        aspect_types = [
          "${local.custom_aspect}/cdmc-classification",
          "${local.system_aspect}/data-quality-scorecard",
          "${local.system_aspect}/contacts",
          "${local.system_aspect}/data-product",
          "${local.system_aspect}/refresh-cadence",
        ]
      }
    },
    var.components.classifier ? {
      "feed-classifier" = {
        topic = "kc-classifier"
        aspect_types = [
          "${local.system_aspect}/sensitive-data-protection-profile",
          "${local.system_aspect}/schema",
        ]
      }
    } : {},
  )
}

resource "google_dataplex_metadata_feed" "feed" {
  for_each = local.feeds

  project          = local.hub_project_id
  location         = local.feed_location
  metadata_feed_id = "${each.key}-${var.env}"
  labels           = local.labels_file.catalog
  pubsub_topic     = local.topic[each.value.topic]

  scope {
    projects = local.feed_scope_projects
  }

  filters {
    aspect_types = each.value.aspect_types
  }
}
