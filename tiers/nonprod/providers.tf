terraform {
  # Contracts §6: Terraform 1.16.x and hashicorp/google 8.10.0 exactly. (The design's §6.11
  # example shows ">= 1.17" and "~> 8.10"; the phase 1 contracts pin these values.)
  required_version = "~> 1.16"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.10.0"
    }
  }
}

# No default project or region: they come from bootstrap/estate.json, which the provider itself
# reads, so every resource names its project and location explicitly.
provider "google" {}
