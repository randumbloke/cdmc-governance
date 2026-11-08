# Custom aspect types (design §5.11) in the hub at location global, and their IAM: each type
# grants aspectTypes.use to its writer's service account only (design §1.5.2, §2.4.1; P6-25).

locals {
  aspect_source = yamldecode(file("${path.module}/../../aspect_types/cdmc_aspect_types.yaml"))

  # One field of a metadataTemplate (Dataplex v1 AspectTypeMetadataTemplate).
  # Arrays and enums are expanded; required becomes constraints.required.
  aspect_shared = local.aspect_source.shared_fields

  aspect_templates = {
    for type_id, t in local.aspect_source.aspect_types : type_id => {
      name = type_id
      type = "record"
      recordFields = concat(
        [for f in t.fields : merge(
          {
            name  = f.name
            type  = f.type
            index = f.index
            annotations = {
              displayName = f.display_name
              description = f.description
            }
          },
          { for k, v in { constraints = { required = true } } : k => v if try(f.required, false) },
          { for k, v in { enumValues = [for i, v in try(f.values, []) : { name = v, index = i + 1 }] } : k => v if f.type == "enum" },
          { for k, v in { arrayItems = { name = try(f.item_name, ""), type = try(f.item_type, "") } } : k => v if f.type == "array" },
        )],
        [
          {
            name        = "evaluation"
            type        = "record"
            index       = t.shared_index
            constraints = { required = true }
            annotations = {
              displayName = local.aspect_shared.evaluation.display_name
              description = local.aspect_shared.evaluation.description
            }
            recordFields = [for f in local.aspect_shared.evaluation.fields : {
              name        = f.name
              type        = f.type
              index       = f.index
              constraints = { required = true }
              annotations = { displayName = f.display_name, description = f.description }
            }]
          },
          {
            name  = "narrative"
            type  = "record"
            index = t.shared_index + 1
            annotations = {
              displayName = local.aspect_shared.narrative.display_name
              description = local.aspect_shared.narrative.description
            }
            recordFields = [for f in local.aspect_shared.narrative.fields : {
              name        = f.name
              type        = f.type
              index       = f.index
              annotations = { displayName = f.display_name, description = f.description }
            }]
          },
          {
            name        = "schema_version"
            type        = "int"
            index       = t.shared_index + 2
            constraints = { required = true }
            annotations = {
              displayName = local.aspect_shared.schema_version.display_name
              description = local.aspect_shared.schema_version.description
            }
          },
        ],
        [for f in try(t.trailing_fields, []) : merge(
          {
            name  = f.name
            type  = f.type
            index = f.index
            annotations = {
              displayName = f.display_name
              description = f.description
            }
          },
          { for k, v in { constraints = { required = true } } : k => v if try(f.required, false) },
        )],
      )
    }
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
  display_name   = local.aspect_source.aspect_types[each.key].display_name
  description    = local.aspect_source.aspect_types[each.key].description
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
