# Offline plan test with a mocked provider and the published files of contracts §3.
# Run: terraform init -backend=false && terraform test (from tiers/nonprod).

mock_provider "google" {}

variables {
  tier              = "nonprod"
  tf_state_bucket   = "tfstate-pltfrm-ngnrng"
  domain_businesses = ["customer", "accounts"]
}

override_data {
  target = data.google_storage_bucket_object_content.estate
  values = {
    content = "{\"organization_id\":\"1059663003036\",\"regions\":[\"australia-southeast1\"],\"environments\":[\"dev\"],\"tiers\":[\"nonprod\"],\"group_domain\":\"mikegyoung.joonix.net\",\"hub_project_ids\":{\"nonprod\":\"kcdda-dgov-hub-nonprod\"},\"cicd_project_id\":\"pltfrm-ngnrng\",\"single_deployer\":true,\"deployer_service_accounts\":{\"apply\":\"tf-deployer@pltfrm-ngnrng.iam.gserviceaccount.com\",\"plan\":\"tf-deployer-plan@pltfrm-ngnrng.iam.gserviceaccount.com\"}}"
  }
}

override_data {
  target = data.google_storage_bucket_object_content.platform_tier
  values = {
    content = "{\"tier\":\"nonprod\",\"hub_project_id\":\"kcdda-dgov-hub-nonprod\",\"hub_project_number\":\"111111111111\",\"service_agents\":{}}"
  }
}

run "phase1_plan" {
  command = plan

  assert {
    condition     = length(google_dataplex_aspect_type.cdmc) == 5
    error_message = "Five custom aspect types (design §5.11)."
  }
  assert {
    condition     = length(google_dataplex_aspect_type_iam_member.writer) == 4
    error_message = "Four evaluator writer grants in dev; the classifier grant is phase 2."
  }
  assert {
    condition     = google_storage_bucket.state.name == "kcdda-dgov-hub-nonprod-dda-state" && google_storage_bucket.state.uniform_bucket_level_access
    error_message = "Hub state bucket name and uniform access."
  }
  assert {
    condition = alltrue([for f in ["domains/", "classification/", "products/dev/customer-dev/", "lineage/dev/accounts-dev/", "bindings/dev/customer-dev/"] :
    contains(keys(google_storage_managed_folder.folder), f)])
    error_message = "Managed folders of design §2.3.2."
  }
  assert {
    condition     = alltrue([for k, m in google_storage_managed_folder_iam_member.writer : m.member == "serviceAccount:tf-deployer@pltfrm-ngnrng.iam.gserviceaccount.com"])
    error_message = "Single deployer writes every folder (design §6.7.2)."
  }
  assert {
    condition     = jsondecode(google_dataplex_aspect_type.cdmc["cdmc-classification"].metadata_template).recordFields[10].name == "schema_fingerprint"
    error_message = "schema_fingerprint is the eleventh field of cdmc-classification."
  }
  assert {
    condition     = length(google_dataplex_glossary_term.term) == 4 && length(google_dataplex_glossary_category.category) == 4
    error_message = "Four glossary categories with one term each."
  }
  assert {
    condition     = google_storage_bucket_object.outputs.name == "outputs/cdmc-governance/tiers/nonprod/outputs.json"
    error_message = "Published outputs path (contracts §3)."
  }
}
