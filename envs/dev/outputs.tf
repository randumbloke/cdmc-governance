locals {
  published = {
    env     = var.env
    domains = local.domains_published
    # Region -> dataset IDs in the hub project (the hub project ID is in the dda-platform tier
    # outputs). Domain scans export to <dq_results>.scan_results (design §3.6).
    hub_datasets = {
      for r in local.regions : r => {
        dq_results   = google_bigquery_dataset.dq_results[r].dataset_id
        sdp_profiles = google_bigquery_dataset.sdp_profiles[r].dataset_id
      }
    }
    cdmc_report_dataset = google_bigquery_dataset.cdmc_report.dataset_id
    # Data project ID -> discovery configuration name. A domain core stack refuses a dataset in
    # a project not listed here (design §6.14.1).
    discovery_configs = { for p, c in google_data_loss_prevention_discovery_config.project : p => c.name }
    metadata_feeds = {
      for f, _ in local.feeds : f => "projects/${local.hub_project_id}/locations/${local.feed_location}/metadataFeeds/${f}-${var.env}"
    }
    service_urls = {
      evaluator = google_cloud_run_v2_service.evaluator.uri
    }
  }
}

# Published values for other repositories (design §6.13.3; schema outputs_governance_env).
resource "google_storage_bucket_object" "outputs" {
  bucket       = var.tf_state_bucket
  name         = "outputs/cdmc-governance/${var.env}/outputs.json"
  content      = jsonencode(local.published)
  content_type = "application/json"

  depends_on = [google_dataplex_metadata_feed.feed]
}

output "published" {
  description = "The values written to outputs/cdmc-governance/<env>/outputs.json."
  value       = local.published
}

output "domains_state_object" {
  description = "Hub state bucket object holding the declared domain state."
  value       = "gs://${local.state_bucket}/${google_storage_bucket_object.domains_state.name}"
}
