# Offline plan test with mocked providers and the published files of contracts §3. Checks that
# the stack's expressions evaluate on the phase 1 estate and that the files it writes have the
# contract shapes. Run: terraform init -backend=false && terraform test (from envs/dev).

mock_provider "google" {}
mock_provider "http" {}

variables {
  env             = "dev"
  tier            = "nonprod"
  tf_state_bucket = "tfstate-pltfrm-ngnrng"
  domains = {
    customer = { display_name = "Customer", description = "Customer domain.", subdomains = ["raw", "staging", "curated", "analytics"] }
    accounts = { display_name = "Accounts", description = "Accounts domain.", subdomains = ["raw", "staging", "curated", "analytics"] }
  }
  components = {
    classifier       = false, steward_inbox = false, access_request_gate = false, reconciler = false
    explainer        = false, scan_generator = false, sdp_notifications = false, access_request_sink = false
    data_access_sink = false, policy_tags = false, evaluator_modules = ["c12", "c14"]
  }
  schedule_times = {
    classifier_daily = "0 1 * * *", evaluator_sweep = "0 2 * * *", gate_sweep = "0 3 * * *"
    reconciler       = "0 4 * * *", reconciler_expiry = "0 * * * *"
  }
  deletion_protection = false
}

override_data {
  target = data.google_storage_bucket_object_content.estate
  values = {
    content = "{\"organization_id\":\"1059663003036\",\"customer_id\":\"C00000000\",\"billing_account\":\"000000-000000-000000\",\"prefix\":\"kcdda\",\"environments\":[\"dev\"],\"tiers\":[\"nonprod\"],\"regions\":[\"australia-southeast1\"],\"group_domain\":\"mikegyoung.joonix.net\",\"hub_project_ids\":{\"nonprod\":\"kcdda-dgov-hub-nonprod\"},\"cicd_project_id\":\"pltfrm-ngnrng\",\"core_data_project_ids\":{\"dev\":\"kcdda-core-dwh-dev\"},\"domain_analytics_project_ids\":{\"dev\":{\"customer\":\"kcdda-customer-analytics-dev\",\"accounts\":\"kcdda-accounts-analytics-dev\"}},\"create_projects\":false,\"manage_project_services\":true,\"manage_service_identities\":true,\"manage_org_policies\":false,\"github_owner_type\":\"user\",\"github_owner\":\"randumbloke\",\"single_deployer\":true,\"tf_state_bucket\":\"tfstate-pltfrm-ngnrng\",\"deployer_service_accounts\":{\"apply\":\"tf-deployer@pltfrm-ngnrng.iam.gserviceaccount.com\",\"plan\":\"tf-deployer-plan@pltfrm-ngnrng.iam.gserviceaccount.com\"}}"
  }
}

override_data {
  target = data.google_storage_bucket_object_content.platform_tier
  values = {
    content = "{\"tier\":\"nonprod\",\"hub_project_id\":\"kcdda-dgov-hub-nonprod\",\"hub_project_number\":\"111111111111\",\"service_agents\":{\"pubsub\":\"service-111111111111@gcp-sa-pubsub.iam.gserviceaccount.com\"}}"
  }
}

override_data {
  target = data.google_storage_bucket_object_content.platform_env
  values = {
    content = "{\"env\":\"dev\",\"folders\":{},\"projects\":{\"core\":{\"project_id\":\"kcdda-core-dwh-dev\",\"number\":\"222222222222\",\"service_agents\":{\"dataplex\":\"service-222222222222@gcp-sa-dataplex.iam.gserviceaccount.com\",\"dlp\":\"service-222222222222@dlp-api.iam.gserviceaccount.com\"}},\"customer\":{\"project_id\":\"kcdda-customer-analytics-dev\",\"number\":\"333333333333\",\"service_agents\":{}},\"accounts\":{\"project_id\":\"kcdda-accounts-analytics-dev\",\"number\":\"444444444444\",\"service_agents\":{}}},\"landing_buckets\":{},\"topics\":{\"kc-evaluator\":\"projects/kcdda-dgov-hub-nonprod/topics/kc-evaluator-dev\",\"kc-evaluator-dlq\":\"projects/kcdda-dgov-hub-nonprod/topics/kc-evaluator-dev-dlq\",\"findings\":\"projects/kcdda-dgov-hub-nonprod/topics/findings-dev\",\"notifications\":\"projects/kcdda-dgov-hub-nonprod/topics/notifications-dev\"},\"metadata_feeds\":{},\"domain_service_accounts\":{\"customer\":{\"ingest\":\"customer-ingest-dev@kcdda-customer-analytics-dev.iam.gserviceaccount.com\",\"analytics\":\"customer-analytics-dev@kcdda-customer-analytics-dev.iam.gserviceaccount.com\"},\"accounts\":{\"ingest\":\"accounts-ingest-dev@kcdda-accounts-analytics-dev.iam.gserviceaccount.com\",\"analytics\":\"accounts-analytics-dev@kcdda-accounts-analytics-dev.iam.gserviceaccount.com\"}}}"
  }
}

override_data {
  target = data.google_storage_bucket_object_content.governance_tier
  values = {
    content = "{\"tier\":\"nonprod\",\"hub_state_bucket\":\"kcdda-dgov-hub-nonprod-dda-state\",\"aspect_types\":{\"cdmc-lineage-evidence\":\"projects/kcdda-dgov-hub-nonprod/locations/global/aspectTypes/cdmc-lineage-evidence\"},\"entry_types\":{},\"inspection_templates\":{\"australia-southeast1\":\"projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/inspectTemplates/dda-shared-australia_southeast1\"}}"
  }
}

# The shim's outputs are known only after apply (data.http reads the created domain), so the
# test supplies them during plan.
override_module {
  target          = module.domain
  override_during = plan
  outputs = {
    name          = "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev"
    policy_member = "principal://dataplex.googleapis.com/projects/111111111111/name/locations/australia-southeast1/dataDomains/customer-dev"
  }
}
override_module {
  target          = module.subdomain
  override_during = plan
  outputs = {
    name          = "projects/kcdda-dgov-hub-nonprod/locations/australia-southeast1/dataDomains/customer-dev-raw"
    policy_member = "principal://dataplex.googleapis.com/projects/111111111111/name/locations/australia-southeast1/dataDomains/customer-dev-raw"
  }
}

run "phase1_plan" {
  command = plan

  assert {
    condition     = length(keys(local.data_projects)) == 3
    error_message = "Expected three data projects (core and two analytics)."
  }
  assert {
    condition     = length(google_data_loss_prevention_discovery_config.project) == 3
    error_message = "One discovery configuration per data project."
  }
  assert {
    condition     = google_bigquery_dataset.dq_results["australia-southeast1"].dataset_id == "dq_results_dev_australia_southeast1"
    error_message = "dq_results dataset name."
  }
  assert {
    condition     = google_bigquery_dataset.cdmc_report.dataset_id == "cdmc_report_dev"
    error_message = "cdmc_report dataset name."
  }
  assert {
    condition     = length(local.subdomains) == 8 && contains(keys(local.subdomains), "customer/curated")
    error_message = "Four subdomains per domain (AT-03)."
  }
  assert {
    condition     = local.subdomains["customer/curated"].id == "customer-dev-curated"
    error_message = "Subdomain IDs are <domain>-<stage>."
  }
  assert {
    condition     = !contains(keys(local.domain_iam["customer"]), "organizations/1059663003036/roles/ddaDomainBinder")
    error_message = "No ddaDomainBinder under single_deployer (design §6.7.2)."
  }
  assert {
    condition     = contains(local.allowed_principals["customer"], "group:dda-customer-producers@mikegyoung.joonix.net")
    error_message = "Producers are allowed in dev (P5-8a)."
  }
  assert {
    condition     = contains(local.allowed_principals["customer"], "serviceAccount:service-333333333333@gcp-sa-dataplex.iam.gserviceaccount.com")
    error_message = "Computed Dataplex agent of the analytics project is allowed."
  }
  assert {
    condition     = local.topic["kc-evaluator"] == "projects/kcdda-dgov-hub-nonprod/topics/kc-evaluator-dev" && local.dlq_topic["findings"] == null
    error_message = "Topic resolution."
  }
  assert {
    condition     = length(google_pubsub_subscription.feed_evaluator.dead_letter_policy) == 1 && length(google_pubsub_subscription.findings_bigquery.dead_letter_policy) == 0
    error_message = "Dead lettering only where the platform publishes a -dlq topic."
  }
  assert {
    condition     = length(google_data_catalog_taxonomy.domain) == 0 && length(google_storage_bucket.steward_inbox) == 0
    error_message = "Phase 2 resources are off in phase 1."
  }
  assert {
    condition     = google_storage_bucket_object.domains_state.name == "domains/dev.json" && google_storage_bucket_object.outputs.name == "outputs/cdmc-governance/dev/outputs.json"
    error_message = "Published object paths (contracts §3)."
  }
  assert {
    condition     = length(local.domains_state.domains) == 2 && length(local.domains_state.domains["customer-dev"].subdomains) == 4
    error_message = "domains/dev.json holds both domains with four subdomains."
  }
  assert {
    condition     = google_cloud_scheduler_job.evaluator_sweep.schedule == "0 2 * * *" && google_cloud_scheduler_job.evaluator_sweep.time_zone == "Australia/Sydney"
    error_message = "Daily sweep at 02:00 Australia/Sydney (design §6.16.2)."
  }
}

run "policy_tags_needs_gate" {
  command = plan

  variables {
    components = {
      classifier       = false, steward_inbox = false, access_request_gate = false, reconciler = false
      explainer        = false, scan_generator = false, sdp_notifications = false, access_request_sink = false
      data_access_sink = false, policy_tags = true, evaluator_modules = ["c12", "c14"]
    }
  }

  expect_failures = [var.components]
}
