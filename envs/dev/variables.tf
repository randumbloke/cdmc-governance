variable "env" {
  description = "Environment of this stack (design §2.1)."
  type        = string
  validation {
    condition     = contains(["dev", "test", "uat", "prod"], var.env)
    error_message = "env must be dev, test, uat or prod."
  }
}

variable "tier" {
  description = "Tier of the hub that serves this environment."
  type        = string
  validation {
    condition     = contains(["nonprod", "prod"], var.tier)
    error_message = "tier must be nonprod or prod."
  }
}

variable "tf_state_bucket" {
  description = "Terraform state bucket holding bootstrap/estate.json and published outputs (design §6.8, §6.13.3)."
  type        = string
}

variable "domains" {
  description = "Business domains of this environment, keyed by business name. The domain ID is <business>-<env> (design §1.6)."
  type = map(object({
    display_name = string
    description  = string
    subdomains   = list(string)
  }))
  validation {
    condition = alltrue(flatten([
      for b, d in var.domains : [for s in d.subdomains : contains(["raw", "staging", "curated", "analytics"], s)]
    ]))
    error_message = "Subdomains are lifecycle stages: raw, staging, curated, analytics."
  }
  validation {
    condition     = alltrue([for b, d in var.domains : can(regex("^[a-z][a-z0-9]*$", b))])
    error_message = "Business names are lower-case letters and digits."
  }
}

variable "components" {
  description = "Component flags by phase (design §6.17; decision P6-31)."
  type = object({
    classifier          = bool
    steward_inbox       = bool
    access_request_gate = bool
    reconciler          = bool
    explainer           = bool
    scan_generator      = bool
    sdp_notifications   = bool
    access_request_sink = bool
    data_access_sink    = bool
    policy_tags         = bool
    evaluator_modules   = list(string)
  })
  validation {
    # Decision P6-36: no policy tag before the gate can grant fine-grained read on it.
    condition     = !var.components.policy_tags || (var.components.access_request_gate && var.components.reconciler)
    error_message = "policy_tags = true needs access_request_gate and reconciler (decision P6-36)."
  }
  validation {
    condition     = alltrue([for m in var.components.evaluator_modules : contains(["c2", "c3", "c5", "c6", "c7", "c8", "c12", "c14"], m)])
    error_message = "evaluator_modules holds control module names: c2, c3, c5, c6, c7, c8, c12, c14."
  }
}

variable "scheduler_time_zone" {
  description = "Time zone of every Cloud Scheduler job (design §6.16.2)."
  type        = string
  default     = "Australia/Sydney"
}

variable "schedule_times" {
  description = "Cron schedule per job, in scheduler_time_zone (design §6.16.2)."
  type        = map(string)
}

variable "rollup_window_minutes" {
  description = "Debounce window of product rollups (design §2.5.2, §6.16.3)."
  type        = number
  default     = 5
}

variable "push_delivery" {
  description = "Push subscription delivery settings (design §2.5.1, §6.16.3)."
  type = object({
    ack_deadline_seconds  = number
    minimum_backoff       = string
    maximum_backoff       = string
    max_delivery_attempts = number
    retention             = string
  })
  default = {
    ack_deadline_seconds  = 60
    minimum_backoff       = "10s"
    maximum_backoff       = "600s"
    max_delivery_attempts = 10
    retention             = "604800s"
  }
}

variable "findings_subscription_schema" {
  description = "How the findings BigQuery subscription maps messages: \"topic\" uses the topic schema cdmc-finding-v1 (design §5.2); \"table\" uses the events table schema, for a topic created without a schema."
  type        = string
  # dda-platform creates the findings topic without a Pub/Sub schema, so the table schema maps
  # the JSON messages (the evaluator's to_message() fields equal the events columns).
  default = "table"
  validation {
    condition     = contains(["topic", "table"], var.findings_subscription_schema)
    error_message = "findings_subscription_schema is topic or table."
  }
}

variable "findings_detail_type" {
  description = "Column type of events.evaluation.detail. VERIFY IN BUILD (VA-61): JSON; fallback STRING, parsed with PARSE_JSON in the views."
  type        = string
  default     = "JSON"
  validation {
    condition     = contains(["JSON", "STRING"], var.findings_detail_type)
    error_message = "findings_detail_type is JSON or STRING."
  }
}

variable "discovery_location" {
  description = "Location of each data project's discovery configuration (design §2.10.1 table: global). VERIFY IN BUILD (VA-39, VA-59)."
  type        = string
  default     = "global"
}

variable "metadata_feed_location" {
  description = "Location of the metadata feeds; null = the home region (design §6.16.3, until VA-59 says otherwise)."
  type        = string
  default     = null
}

variable "compliance_reviewers_group" {
  description = "Group granted read on cdmc_report (design §1.5.1), for example dda-compliance-reviewers@<group domain>. Empty: no grant (the group is not in the phase 1 asks)."
  type        = string
  default     = ""
}

variable "alert_notification_emails" {
  description = "Email addresses of the governance engineers, the recipients of the §5.8 alerts. One email notification channel each."
  type        = list(string)
  default     = []
}

variable "alert_notification_channels" {
  description = "Existing notification channel IDs added to every §5.8 alert policy."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "Deletion protection on Cloud Run services, jobs and report tables."
  type        = bool
  default     = true
}
