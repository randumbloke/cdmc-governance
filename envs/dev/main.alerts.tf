# Monitoring (design §5.8): Cloud Monitoring alert policies on Pub/Sub, Cloud Run and log-based
# conditions, created with the control plane. Phase 1 (design §6.17) needs the indicators whose
# component runs: dead-letter topics empty, findings backlog age, and the daily sweep.
#
# Not declared in phase 1:
# - Classification latency: the classifier is phase 2.
# - Gate request-to-check time, gate sweep and reconciler jobs: later phases.
# - Sweep coverage (coverage_daily) and the data_assets day-on-day fall: both read data_assets,
#   which the phase 1 evaluator does not write (README open point 1). They need a scheduled
#   query or a log-based metric from the sweep and are added with the C5 module.

locals {
  alert_labels = { "dda-component" = "evaluator", "dda-env" = var.env }

  # Short topic ID (last path segment) of each dead-letter topic the platform publishes.
  alert_dlq_topics = {
    for k, t in local.dlq_topic : k => element(split("/", t), length(split("/", t)) - 1) if t != null
  }

  alert_channels = concat(
    var.alert_notification_channels,
    [for c in google_monitoring_notification_channel.email : c.id],
  )
}

# Governance engineers (design §5.8 "Alert to"), by email.
resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.alert_notification_emails)

  project      = local.hub_project_id
  display_name = "DDA governance engineers (${var.env}): ${each.key}"
  type         = "email"
  labels = {
    email_address = each.key
  }
}

# Dead-letter topics: empty. Any message dead-lettered is reprocessed by the next sweep, but the
# governance engineers are told (design §2.5.1, §5.8).
resource "google_monitoring_alert_policy" "dead_letter" {
  for_each = local.alert_dlq_topics

  project      = local.hub_project_id
  display_name = "DDA ${var.env}: message dead-lettered on ${each.value}"
  combiner     = "OR"
  user_labels  = local.alert_labels

  conditions {
    display_name = "Messages published to ${each.value}"
    condition_threshold {
      filter          = "resource.type = \"pubsub_topic\" AND resource.labels.topic_id = \"${each.value}\" AND metric.type = \"pubsub.googleapis.com/topic/send_message_operation_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "A message on `${each.key}` failed ${var.push_delivery.max_delivery_attempts} deliveries and was dead-lettered. The daily sweep re-evaluates every asset; check the evaluator logs for the cause (design §2.5.1)."
  }

  notification_channels = local.alert_channels
}

# findings subscription backlog age under 10 minutes (design §5.8).
resource "google_monitoring_alert_policy" "findings_backlog" {
  project      = local.hub_project_id
  display_name = "DDA ${var.env}: findings subscription backlog older than 10 minutes"
  combiner     = "OR"
  user_labels  = local.alert_labels

  conditions {
    display_name = "Oldest unacked message age on ${google_pubsub_subscription.findings_bigquery.name}"
    condition_threshold {
      filter          = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${google_pubsub_subscription.findings_bigquery.name}\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      comparison      = "COMPARISON_GT"
      threshold_value = 600
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Findings are not reaching `cdmc_report.events`. Check the BigQuery subscription's state and the Pub/Sub agent's grant on the dataset (design §5.2)."
  }

  notification_channels = local.alert_channels
}

# Sweep job completes daily (design §5.8): a failed execution of the sweep job...
resource "google_monitoring_alert_policy" "sweep_failed" {
  project      = local.hub_project_id
  display_name = "DDA ${var.env}: evaluator sweep execution failed"
  combiner     = "OR"
  user_labels  = local.alert_labels

  conditions {
    display_name = "Failed executions of ${google_cloud_run_v2_job.evaluator_sweep.name}"
    condition_threshold {
      filter          = "resource.type = \"cloud_run_job\" AND resource.labels.job_name = \"${google_cloud_run_v2_job.evaluator_sweep.name}\" AND metric.type = \"run.googleapis.com/job/completed_execution_count\" AND metric.labels.result = \"failed\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "The daily sweep did not complete, so assets without events were not evaluated today (design §5.1, AT-13). Re-run the job after fixing the cause."
  }

  notification_channels = local.alert_channels
}

# ...and a scheduler attempt that could not start it (the job never ran).
resource "google_monitoring_alert_policy" "sweep_not_started" {
  project      = local.hub_project_id
  display_name = "DDA ${var.env}: evaluator sweep could not be started"
  combiner     = "OR"
  user_labels  = local.alert_labels

  conditions {
    display_name = "Cloud Scheduler errors for ${google_cloud_scheduler_job.evaluator_sweep.name}"
    condition_matched_log {
      filter = "resource.type = \"cloud_scheduler_job\" AND resource.labels.job_id = \"${google_cloud_scheduler_job.evaluator_sweep.name}\" AND severity >= ERROR"
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
    auto_close = "86400s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Cloud Scheduler could not run the sweep job. Check that evaluator-${var.env} holds run.invoker on the job and that the job exists."
  }

  notification_channels = local.alert_channels
}
