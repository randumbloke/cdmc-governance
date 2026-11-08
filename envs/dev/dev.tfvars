env             = "dev"
tier            = "nonprod"
tf_state_bucket = "tfstate-pltfrm-ngnrng"

# Domains of this environment (design §1.7, §6.17). Domain ID = <business>-<env>; four lifecycle
# subdomains each (AT-03).
domains = {
  customer = {
    display_name = "Customer"
    description  = "Customer domain: customer master and contact data, and the Customer Profile product."
    subdomains   = ["raw", "staging", "curated", "analytics"]
  }
  accounts = {
    display_name = "Accounts"
    description  = "Accounts domain: account reference data, and the account summary product."
    subdomains   = ["raw", "staging", "curated", "analytics"]
  }
}

# Phase 1 (design §6.17).
components = {
  classifier          = false
  steward_inbox       = false
  access_request_gate = false
  reconciler          = false
  explainer           = false
  scan_generator      = false
  sdp_notifications   = false
  access_request_sink = false
  data_access_sink    = false
  policy_tags         = false
  evaluator_modules   = ["c12", "c14"]
}

scheduler_time_zone = "Australia/Sydney"
schedule_times = {
  classifier_daily  = "0 1 * * *"
  evaluator_sweep   = "0 2 * * *"
  gate_sweep        = "0 3 * * *"
  reconciler        = "0 4 * * *"
  reconciler_expiry = "0 * * * *"
}

# Dev only: lets the stack be destroyed in reverse apply order (change design, rollback).
deletion_protection = false
