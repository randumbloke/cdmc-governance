# Control evaluator (design §5.1): Cloud Run service (events, rollups, published product
# definitions) and Cloud Run job (daily sweep), both as evaluator-<env>, by image digest from
# envs/images.json (design §6.10). Phase 1 modules: c12, c14 and the contract writer (§6.17).

locals {
  evaluator_service_name = "evaluator-${var.env}"
  evaluator_job_name     = "evaluator-sweep-${var.env}"

  # Deterministic run.app URL, known before the service exists, so the service can give Cloud
  # Tasks its own URL as the rollup target without a dependency cycle.
  evaluator_url = "https://${local.evaluator_service_name}-${local.hub_project_number}.${local.home_region}.run.app"

  evaluator_labels = merge(local.labels_file.cloud_run, { "dda-component" = "evaluator" })

  # Names as read by kc-control-plane cdmc_common.config.Settings.from_env.
  evaluator_env = {
    DDA_ENV               = var.env
    HUB_PROJECT_ID        = local.hub_project_id
    REGION                = local.home_region
    CICD_PROJECT_ID       = local.cicd_project_id
    HUB_STATE_BUCKET      = local.state_bucket
    FINDINGS_TOPIC        = local.topic["findings"]
    DQ_RESULTS_TABLE      = "${local.hub_project_id}.${google_bigquery_dataset.dq_results[local.home_region].dataset_id}.scan_results"
    ROLLUP_QUEUE          = local.rollup_queue
    ROLLUP_HANDLER_URL    = "${local.evaluator_url}/tasks/rollup"
    ROLLUP_INVOKER_SA     = local.evaluator_sa
    ROLLUP_WINDOW_SECONDS = tostring(var.rollup_window_minutes * 60)
    DATA_PROJECTS         = join(",", keys(local.data_projects))
    SINGLE_DEPLOYER       = tostring(local.single_deployer)
    SCHEDULER_TIME_ZONE   = var.scheduler_time_zone
    EVALUATOR_MODULES     = join(",", var.components.evaluator_modules)
  }
}

resource "google_cloud_run_v2_service" "evaluator" {
  project     = local.hub_project_id
  location    = local.home_region
  name        = local.evaluator_service_name
  description = "CDMC control evaluator (design §5.1)."
  labels      = local.evaluator_labels

  # Only Pub/Sub, Eventarc, Cloud Scheduler and Cloud Tasks in the hub call it (design §2.1.1).
  # VERIFY IN BUILD (VA-52): that these sources count as internal traffic.
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = var.deletion_protection

  template {
    service_account                  = local.evaluator_sa
    max_instance_request_concurrency = 10
    timeout                          = "300s"
    labels                           = local.evaluator_labels

    scaling {
      max_instance_count = 50
    }

    containers {
      image = local.images["evaluator"]

      dynamic "env" {
        for_each = local.evaluator_env
        content {
          name  = env.key
          value = env.value
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}

resource "google_cloud_run_v2_job" "evaluator_sweep" {
  project             = local.hub_project_id
  location            = local.home_region
  name                = local.evaluator_job_name
  labels              = local.evaluator_labels
  deletion_protection = var.deletion_protection

  template {
    # Task i takes the data projects whose hash modulo 20 is i (design §5.1).
    task_count  = 20
    parallelism = 20
    labels      = local.evaluator_labels

    template {
      service_account = local.evaluator_sa
      timeout         = "3600s"
      max_retries     = 1

      containers {
        image   = local.images["evaluator-sweep"]
        command = ["evaluator-sweep"]

        dynamic "env" {
          for_each = local.evaluator_env
          content {
            name  = env.key
            value = env.value
          }
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    }
  }
}

# Every caller authenticates as evaluator-<env> (design §2.4, §2.5.1), which holds run.invoker
# on its own service and job (run.invoker includes run.jobs.run).
resource "google_cloud_run_v2_service_iam_member" "evaluator_invoker" {
  project  = local.hub_project_id
  location = local.home_region
  name     = google_cloud_run_v2_service.evaluator.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.evaluator_sa}"
}

resource "google_cloud_run_v2_job_iam_member" "evaluator_invoker" {
  project  = local.hub_project_id
  location = local.home_region
  name     = google_cloud_run_v2_job.evaluator_sweep.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.evaluator_sa}"
}
