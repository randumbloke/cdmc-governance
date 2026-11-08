# Shared inspection template, one per region (design §1.3, §6.13.2). Discovery configurations
# in each data project (envs/<env>/main.discovery.tf) reference the template of their region.
# VERIFY IN BUILD (VA-39): that a project-level discovery configuration can reference a template
# in the hub. Fallback (ADR-010): an identical copy of the template in each data project.

resource "google_data_loss_prevention_inspect_template" "shared" {
  for_each = toset(local.regions)

  parent       = "projects/${local.hub_project_id}/locations/${each.key}"
  template_id  = "dda-shared-${replace(each.key, "-", "_")}"
  display_name = "DDA shared inspection template (${each.key})"
  description  = "Shared infoTypes for Sensitive Data Protection discovery in the DDA data projects."

  inspect_config {
    min_likelihood = var.inspect_min_likelihood
    include_quote  = false

    dynamic "info_types" {
      for_each = var.inspect_info_types
      content {
        name = info_types.value
      }
    }
  }
}
