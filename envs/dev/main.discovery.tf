# Sensitive Data Protection discovery, one configuration per data project (design §1.3, §5.3;
# decision P6-24; ADR-010 K2). Phase 1 exports profiles to sdp_profiles_<env>_<region> without
# notifications (design §6.17, AT-10); sdp_notifications adds them in phase 2.
#
# VERIFY IN BUILD (VA-39): a project-level configuration referencing the hub's template.
# VERIFY IN BUILD (VA-59): export target in the same location as the data.
# VERIFY IN BUILD (VA-37): the export holds the column profile fields the classifier reads.
# VERIFY IN BUILD (VA-36): publish_to_dataplex_catalog attaches the profile aspect to entries.
# VA-38 (confirmed at 8.10.0): the four action and cadence arguments exist.

locals {
  # Data projects hold their data in the home region (single-region estate, design §2.1); the
  # template and export dataset of that region are used. SDP DiscoveryConfig requires a
  # non-global location matching the template region (VA-39, VA-59).
  discovery_region   = local.home_region
  discovery_location = coalesce(var.discovery_location, local.discovery_region)

  sdp_events = ["NEW_PROFILE", "CHANGED_PROFILE", "SCORE_INCREASED"]
}

resource "google_data_loss_prevention_discovery_config" "project" {
  for_each = local.data_projects

  parent       = "projects/${each.key}/locations/${local.discovery_location}"
  location     = local.discovery_location
  display_name = "dda-discovery-${var.env}"
  status       = "RUNNING"

  inspect_templates = [local.governance_tier.inspection_templates[local.discovery_region]]

  targets {
    big_query_target {
      filter {
        other_tables {}
      }
      cadence {
        schema_modified_cadence {
          types     = ["SCHEMA_NEW_COLUMNS", "SCHEMA_REMOVED_COLUMNS"]
          frequency = "UPDATE_FREQUENCY_DAILY"
        }
        table_modified_cadence {
          types     = ["TABLE_MODIFIED_TIMESTAMP"]
          frequency = "UPDATE_FREQUENCY_DAILY"
        }
        inspect_template_modified_cadence {
          frequency = "UPDATE_FREQUENCY_DAILY"
        }
      }
    }
  }

  actions {
    export_data {
      profile_table {
        project_id = local.hub_project_id
        dataset_id = google_bigquery_dataset.sdp_profiles[local.discovery_region].dataset_id
        table_id   = "profiles"
      }
    }
  }

  actions {
    publish_to_dataplex_catalog {}
  }

  # Phase 2: profile notifications to the classifier (design §2.5).
  dynamic "actions" {
    for_each = var.components.sdp_notifications ? toset(local.sdp_events) : toset([])
    content {
      pub_sub_notification {
        topic             = local.topic["sdp-profiles"]
        event             = actions.value
        detail_of_message = "TABLE_PROFILE"
      }
    }
  }

  # The agent's grants come first; a grant that has not propagated fails the first attempt and
  # the build's single retry completes it (design §6.14.3; P6-27).
  depends_on = [
    google_bigquery_dataset_access.sdp_profiles_dlp_agent,
  ]
}

# The SDP agents' publisher grants on sdp-profiles are made by dda-platform with the topic
# (dda-platform envs/dev/main.topics.tf), so none is declared here.
