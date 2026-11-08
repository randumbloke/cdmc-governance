locals {
  published = {
    tier             = var.tier
    hub_state_bucket = google_storage_bucket.state.name
    aspect_types     = { for k, v in google_dataplex_aspect_type.cdmc : k => v.id }
    # The design names no custom entry type for phase 1 (or later): every governed asset is a
    # system entry (BigQuery table, data product). The key stays for the contract.
    entry_types          = {}
    inspection_templates = { for r, t in google_data_loss_prevention_inspect_template.shared : r => t.id }
  }
}

# Published values for other repositories (design §6.13.3; schema outputs_governance_tier).
resource "google_storage_bucket_object" "outputs" {
  bucket       = var.tf_state_bucket
  name         = "outputs/cdmc-governance/tiers/${var.tier}/outputs.json"
  content      = jsonencode(local.published)
  content_type = "application/json"
}

output "published" {
  description = "The values written to outputs/cdmc-governance/tiers/<tier>/outputs.json."
  value       = local.published
}

output "glossary" {
  description = "Glossary resource name."
  value       = google_dataplex_glossary.governance.name
}
