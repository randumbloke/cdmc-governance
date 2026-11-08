# Custom aspect types (design §5.11) in the hub at location global, and their IAM: each type
# grants aspectTypes.use to its writer's service account only (design §1.5.2, §2.4.1; P6-25).
# VERIFY IN BUILD (VA-42, VA-76): custom aspects are refused without aspectTypes.use, and
# roles/dataplex.aspectTypeUser plus ddaAspectWriter is enough for the writer.

locals {
  # Vendored single source (design §5.11): each type's metadataTemplate is passed as is.
  aspect_source = yamldecode(file("${path.module}/../../aspect_types/cdmc_aspect_types.yaml"))

  aspect_templates = { for type_id, t in local.aspect_source.aspect_types : type_id => t.metadataTemplate }

  aspect_descriptions = {
    "cdmc-classification"        = { display_name = "CDMC classification", description = "Classification level of a BigQuery table or column, with its provenance (C6). Writer: the classifier." }
    "cdmc-provisioning-point"    = { display_name = "CDMC provisioning point", description = "Whether a BigQuery table is a provisioning point (C3). Writer: the C3 module of the control evaluator." }
    "cdmc-lineage-evidence"      = { display_name = "CDMC lineage evidence", description = "Run-time and design-time ultimate sources of a BigQuery table (C14). Writer: the C14 module of the control evaluator." }
    "cdmc-data-product-contract" = { display_name = "CDMC data product contract", description = "Owner inputs of a data product contract. Writer: the contract writer of the control evaluator." }
    "cdmc-data-product-quality"  = { display_name = "CDMC data product quality", description = "Pooled quality score, status and freshness of a data product (C12). Writer: the C12 module of the control evaluator." }
  }

  # Writer of each aspect type (design §1.5.2). The classifier is phase 2 (design §6.17).
  aspect_writers = merge(
    {
      for pair in setproduct(
        ["cdmc-provisioning-point", "cdmc-lineage-evidence", "cdmc-data-product-contract", "cdmc-data-product-quality"],
        local.tier_envs,
      ) : "${pair[0]}/${pair[1]}" => { aspect_type = pair[0], member = "serviceAccount:${local.evaluator_sa[pair[1]]}" }
    },
    {
      for e in local.tier_envs : "cdmc-classification/${e}" => {
        aspect_type = "cdmc-classification", member = "serviceAccount:${local.classifier_sa[e]}"
      } if var.classifier_enabled
    },
  )
}

resource "google_dataplex_aspect_type" "cdmc" {
  for_each = local.aspect_templates

  project        = local.hub_project_id
  location       = "global"
  aspect_type_id = each.key
  display_name   = local.aspect_descriptions[each.key].display_name
  description    = local.aspect_descriptions[each.key].description
  labels         = local.labels_file.catalog

  metadata_template = jsonencode(each.value)
}

resource "google_dataplex_aspect_type_iam_member" "writer" {
  for_each = local.aspect_writers

  project        = local.hub_project_id
  location       = "global"
  aspect_type_id = google_dataplex_aspect_type.cdmc[each.value.aspect_type].aspect_type_id
  role           = "roles/dataplex.aspectTypeUser"
  member         = each.value.member
}
