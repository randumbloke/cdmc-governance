# Governance glossary (design §1.3, §4.2.1; decision P4-2), one per hub at location global.

locals {
  glossary = yamldecode(file("${path.module}/../../glossary/glossary.yaml"))

  glossary_terms = merge([
    for c_id, c in local.glossary.categories : {
      for t_id, t in c.terms : "${c_id}/${t_id}" => merge(t, { category = c_id, term_id = t_id })
    }
  ]...)
}

resource "google_dataplex_glossary" "governance" {
  project      = local.hub_project_id
  location     = "global"
  glossary_id  = local.glossary.glossary_id
  display_name = local.glossary.display_name
  description  = local.glossary.description
  labels       = local.labels_file.catalog
}

resource "google_dataplex_glossary_category" "category" {
  for_each = local.glossary.categories

  project      = local.hub_project_id
  location     = "global"
  glossary_id  = google_dataplex_glossary.governance.glossary_id
  category_id  = each.key
  parent       = "projects/${local.hub_project_id}/locations/global/glossaries/${google_dataplex_glossary.governance.glossary_id}"
  display_name = each.value.display_name
  description  = each.value.description
  labels       = local.labels_file.catalog
}

resource "google_dataplex_glossary_term" "term" {
  for_each = local.glossary_terms

  project     = local.hub_project_id
  location    = "global"
  glossary_id = google_dataplex_glossary.governance.glossary_id
  term_id     = each.value.term_id
  # A term's parent is its category, so the term ID is the label value and the category is the
  # label (design §4.2.1).
  parent       = google_dataplex_glossary_category.category[each.value.category].name
  display_name = each.value.display_name
  description  = each.value.description
  labels       = local.labels_file.catalog
}
