# Daily sweep (design §5.1, §6.16.2): Cloud Scheduler runs the sweep job at 02:00 local, after
# the classifier's 01:00 run. The Cloud Run Admin API takes an OAuth token, not an OIDC token.

resource "google_cloud_scheduler_job" "evaluator_sweep" {
  project     = local.hub_project_id
  region      = local.home_region
  name        = "evaluator-sweep-${var.env}"
  description = "Daily evaluator sweep (design §5.1); AT-13."
  schedule    = var.schedule_times["evaluator_sweep"]
  time_zone   = var.scheduler_time_zone

  attempt_deadline = "180s"

  retry_config {
    retry_count          = 3
    min_backoff_duration = "60s"
    max_backoff_duration = "600s"
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${local.hub_project_id}/locations/${local.home_region}/jobs/${google_cloud_run_v2_job.evaluator_sweep.name}:run"

    oauth_token {
      service_account_email = local.evaluator_sa
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.evaluator_invoker]
}
