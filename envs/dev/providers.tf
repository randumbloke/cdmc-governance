terraform {
  # Contracts §6: Terraform 1.16.x, hashicorp/google 8.10.0 exactly, hashicorp/http ~> 3.6.
  required_version = "~> 1.16"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.10.0"
    }
    # Used only inside dda-platform//modules/data_domain_shim/domain (data.http.domain reads a
    # domain's policyMember, design §2.3.2); declared here so the lock file pins it.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}

# No default project or region: they come from bootstrap/estate.json, which the provider itself
# reads, so every resource names its project and location explicitly.
provider "google" {}
