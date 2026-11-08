# Event wiring of the evaluator (design §2.5, §2.5.1). Topics, dead-letter topics, the metadata
# feed and the rollup queue are dda-platform's; the subscriptions and triggers that need the
# service URL are here (decision P6-24; ddaSubscriptionAdmin, VERIFY IN BUILD (VA-99)).

# feed-evaluator events (topic kc-evaluator-<env>) pushed to the evaluator.
# VERIFY IN BUILD (VA-09): the feed's event payload shape.
resource "google_pubsub_subscription" "feed_evaluator" {
  project = local.hub_project_id
  name    = "feed-evaluator-${var.env}-push"
  topic   = local.topic["kc-evaluator"]
  labels  = local.evaluator_labels

  ack_deadline_seconds       = var.push_delivery.ack_deadline_seconds
  message_retention_duration = var.push_delivery.retention

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.evaluator.uri}/events/kc"
    oidc_token {
      service_account_email = local.evaluator_sa
      audience              = google_cloud_run_v2_service.evaluator.uri
    }
  }

  retry_policy {
    minimum_backoff = var.push_delivery.minimum_backoff
    maximum_backoff = var.push_delivery.maximum_backoff
  }

  dynamic "dead_letter_policy" {
    for_each = local.dlq_topic["kc-evaluator"] == null ? [] : [local.dlq_topic["kc-evaluator"]]
    content {
      dead_letter_topic     = dead_letter_policy.value
      max_delivery_attempts = var.push_delivery.max_delivery_attempts
    }
  }

  expiration_policy {
    ttl = ""
  }

  depends_on = [google_cloud_run_v2_service_iam_member.evaluator_invoker]
}

# Findings into cdmc_report.events (design §5.2). VERIFY IN BUILD (VA-61): the Avro detail
# field written to a JSON column.
resource "google_pubsub_subscription" "findings_bigquery" {
  project = local.hub_project_id
  name    = "findings-${var.env}-bigquery"
  topic   = local.topic["findings"]
  labels  = local.labels_file.hub_dataset

  message_retention_duration = var.push_delivery.retention

  bigquery_config {
    table               = "${local.hub_project_id}.${google_bigquery_dataset.cdmc_report.dataset_id}.${google_bigquery_table.events.table_id}"
    use_topic_schema    = var.findings_subscription_schema == "topic"
    use_table_schema    = var.findings_subscription_schema == "table"
    write_metadata      = false
    drop_unknown_fields = true
  }

  dynamic "dead_letter_policy" {
    for_each = local.dlq_topic["findings"] == null ? [] : [local.dlq_topic["findings"]]
    content {
      dead_letter_topic     = dead_letter_policy.value
      max_delivery_attempts = var.push_delivery.max_delivery_attempts
    }
  }

  expiration_policy {
    ttl = ""
  }

  # The Pub/Sub agent's grant comes first; the build's retry covers propagation (design §6.14.3).
  depends_on = [google_bigquery_dataset_access.cdmc_report_pubsub_agent]
}

# Dead lettering needs the Pub/Sub agent as subscriber on the source subscription; publisher on
# each -dlq topic is granted by dda-platform, which owns the topics.
resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  for_each = {
    for k, s in {
      "kc-evaluator" = google_pubsub_subscription.feed_evaluator.name
      "findings"     = google_pubsub_subscription.findings_bigquery.name
    } : k => s if local.dlq_topic[k] != null
  }

  project      = local.hub_project_id
  subscription = each.value
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.pubsub_agent}"
}

# Uploads of published product definitions and lineage manifests to the hub state bucket call
# the evaluator through their audit event (design §2.3.2, §2.5, §3.2.1). The evaluator checks
# the uploader in the event. Scoped to this environment's folders.
# VERIFY IN BUILD (no VA ID): the path pattern operator on resourceName for Cloud Storage audit
# events, and the trigger location (bucket region).
resource "google_eventarc_trigger" "state_objects" {
  for_each = toset(["products", "lineage"])

  project         = local.hub_project_id
  location        = local.home_region
  name            = "evaluator-${each.key}-${var.env}"
  service_account = local.evaluator_sa
  labels          = local.evaluator_labels

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  matching_criteria {
    attribute = "serviceName"
    value     = "storage.googleapis.com"
  }
  matching_criteria {
    attribute = "methodName"
    value     = "storage.objects.create"
  }
  matching_criteria {
    attribute = "resourceName"
    operator  = "match-path-pattern"
    value     = "projects/_/buckets/${local.state_bucket}/objects/${each.key}/${var.env}/**"
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.evaluator.name
      region  = local.home_region
      path    = "/events/state"
    }
  }

  depends_on = [google_cloud_run_v2_service_iam_member.evaluator_invoker]
}
