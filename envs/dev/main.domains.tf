# Data domains and their lifecycle subdomains, through the `domain` submodule of the data domain
# shim (design §2.3; ADR-008). Only this stack calls `domain` (decisions P6-8, P6-32). Inputs and
# outputs are exactly those of the design §2.3 tables.
#
# VERIFY IN BUILD (VA-17): domains are regional (created in the home region); if they must be
# global, `location` becomes "global".
# VERIFY IN BUILD (VA-62): patch changes contacts and labels in place; setIamPolicy accepts the
# allowed roles. VERIFY IN BUILD (VA-96): operation polling. VERIFY IN BUILD (VA-12): the
# policy_member output can be granted a role like any other principal.

locals {
  domain_id = { for b, d in var.domains : b => "${b}-${var.env}" }

  # Groups (contracts §2; design §1.5.1, §2.4.6). They exist before this stack runs (task 2.5).
  owners_group    = { for b, d in var.domains : b => "dda-${b}-${var.env}-owners@${local.group_domain}" }
  stewards_group  = { for b, d in var.domains : b => "dda-${b}-${var.env}-stewards@${local.group_domain}" }
  producers_group = { for b, d in var.domains : b => "dda-${b}-producers@${local.group_domain}" }

  # Organisation custom roles (design §1.5.2, §2.4.7), created by bootstrap.
  role_metadata_steward = "organizations/${local.org_id}/roles/ddaMetadataSteward"
  role_domain_binder    = "organizations/${local.org_id}/roles/ddaDomainBinder"

  # Domain IAM: only the module's allowed roles (design §2.3). Stewards curate metadata of bound
  # resources (VERIFY IN BUILD (VA-48)); owners and producers view the domain. ddaDomainBinder
  # goes to the domain's own pipeline only, and is not granted under single_deployer, because
  # tf-deployer's roles/dataplex.dataDomainAdmin covers binding (design §6.7.1, §6.7.2).
  domain_iam = {
    for b, d in var.domains : b => merge(
      {
        (local.role_metadata_steward)     = ["group:${local.stewards_group[b]}"]
        "roles/dataplex.dataDomainViewer" = ["group:${local.owners_group[b]}", "group:${local.producers_group[b]}"]
      },
      {
        for role, members in { (local.role_domain_binder) = ["serviceAccount:${local.domain_pipeline[b]}"] } :
        role => members if !local.single_deployer
      },
    )
  }

  # Contacts (design §2.3; C2): the owner and steward groups. contactRole values follow the API's
  # examples (owner, steward).
  domain_contacts = {
    for b, d in var.domains : b => [
      { role = "owner", identity = local.owners_group[b] },
      { role = "steward", identity = local.stewards_group[b] },
    ]
  }

  # Subdomain IDs. Domain IDs share one namespace per project and location
  # (projects/{p}/locations/{l}/dataDomains/{id}), so two domains cannot both have a child called
  # "raw"; the subdomain ID is <domain>-<stage> and the stage stays the key in every file.
  subdomains = merge([
    for b, d in var.domains : {
      for s in d.subdomains : "${b}/${s}" => { business = b, stage = s, id = "${local.domain_id[b]}-${s}" }
    }
  ]...)
}

module "domain" {
  source   = "git::https://github.com/randumbloke/dda-platform.git//modules/data_domain_shim/domain?ref=main"
  for_each = var.domains

  project        = local.hub_project_id
  location       = local.home_region
  data_domain_id = local.domain_id[each.key]
  display_name   = "${each.value.display_name} (${var.env})"
  description    = each.value.description
  contacts       = local.domain_contacts[each.key]
  labels         = merge(local.labels_file.data_domain, { "dda-domain" = local.domain_id[each.key] })
  iam_members    = local.domain_iam[each.key]
}

module "subdomain" {
  source   = "git::https://github.com/randumbloke/dda-platform.git//modules/data_domain_shim/domain?ref=main"
  for_each = local.subdomains

  project            = local.hub_project_id
  location           = local.home_region
  data_domain_id     = each.value.id
  parent_data_domain = module.domain[each.value.business].name
  display_name       = "${var.domains[each.value.business].display_name} ${each.value.stage} (${var.env})"
  description        = "Lifecycle subdomain ${each.value.stage} of ${local.domain_id[each.value.business]}."
  contacts           = local.domain_contacts[each.value.business]
  labels = merge(local.labels_file.data_domain, {
    "dda-domain" = local.domain_id[each.value.business]
    "dda-stage"  = each.value.stage
  })
  # Bindings are made to subdomains; the domain grants above are on the parent. Whether a parent
  # grant reaches a child's bound resources is part of VERIFY IN BUILD (VA-48, VA-87).
  iam_members = {}
}

locals {
  # Allowed-principal set of each domain (design §5.4 table), used by C3 and C7.
  domain_projects = {
    for b, d in var.domains : b => distinct(compact([
      local.platform_env.projects["core"].project_id,
      try(local.platform_env.projects[b].project_id, ""),
    ]))
  }

  allowed_principals = {
    for b, d in var.domains : b => sort(distinct(concat(
      # Producer identities: the domain's ingest and analytics service accounts.
      [
        "serviceAccount:${local.platform_env.domain_service_accounts[b].ingest}",
        "serviceAccount:${local.platform_env.domain_service_accounts[b].analytics}",
      ],
      # Producers group, in non-production only (decision P5-8a).
      contains(["dev", "test"], var.env) ? ["group:${local.producers_group[b]}"] : [],
      # Owner group.
      ["group:${local.owners_group[b]}"],
      # Dataplex and SDP agents of each data project holding the domain's datasets.
      flatten([for p in local.domain_projects[b] : [
        "serviceAccount:${local.dataplex_agent[p]}",
        "serviceAccount:${local.dlp_agent[p]}",
      ]]),
      # The domain's and its subdomains' policy members (ddaDomainDelegate, no data permission).
      [module.domain[b].policy_member],
      [for k, s in local.subdomains : module.subdomain[k].policy_member if s.business == b],
      # The Terraform pipeline that creates the domain's datasets and sets their IAM.
      ["serviceAccount:${local.domain_pipeline[b]}"],
    )))
  }

  domains_published = {
    for b, d in var.domains : local.domain_id[b] => {
      name          = module.domain[b].name
      policy_member = module.domain[b].policy_member
      subdomains = {
        for k, s in local.subdomains : s.stage => {
          name          = module.subdomain[k].name
          policy_member = module.subdomain[k].policy_member
        } if s.business == b
      }
    }
  }

  # Declared domain state (design §2.3.2, §5.4; schema domains_state).
  domains_state = {
    env = var.env
    domains = {
      for b, d in var.domains : local.domain_id[b] => merge(local.domains_published[local.domain_id[b]], {
        contacts           = local.domain_contacts[b]
        iam                = local.domain_iam[b]
        allowed_principals = local.allowed_principals[b]
      })
    }
  }
}

# One writer per file (decision P6-32): this stack writes domains/<env>.json in the managed
# folder domains/, where only the governance pipeline holds objectCreator.
resource "google_storage_bucket_object" "domains_state" {
  bucket       = local.state_bucket
  name         = "domains/${var.env}.json"
  content      = jsonencode(local.domains_state)
  content_type = "application/json"
}
