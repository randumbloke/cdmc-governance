variable "tier" {
  description = "Hub tier this stack configures (design §2.1)."
  type        = string
  validation {
    condition     = contains(["nonprod", "prod"], var.tier)
    error_message = "tier must be nonprod or prod."
  }
}

variable "tf_state_bucket" {
  description = "Terraform state bucket holding bootstrap/estate.json and the published outputs (design §6.8, §6.13.3)."
  type        = string
}

variable "domain_businesses" {
  description = "Business names of the domains served by this tier (customer, accounts). Each gets products/, lineage/ and bindings/ managed folders per environment (design §2.3.2)."
  type        = list(string)
  validation {
    condition     = alltrue([for b in var.domain_businesses : can(regex("^[a-z][a-z0-9]*$", b))])
    error_message = "Business names are lower-case letters and digits."
  }
}

variable "classifier_enabled" {
  description = "Phase 2 flag (design §6.17): grant classifier-<env> aspectTypes.use on cdmc-classification and read on the classification/ and domains/ folders."
  type        = bool
  default     = false
}

variable "inspect_info_types" {
  description = "Built-in infoTypes of the shared inspection template (design §1.3; ADR-010)."
  type        = list(string)
  default = [
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "PERSON_NAME",
    "STREET_ADDRESS",
    "DATE_OF_BIRTH",
    "CREDIT_CARD_NUMBER",
    "IBAN_CODE",
    "AUSTRALIA_TAX_FILE_NUMBER",
    "AUSTRALIA_MEDICARE_NUMBER",
    "AUSTRALIA_DRIVERS_LICENSE_NUMBER",
    "AUSTRALIA_PASSPORT",
  ]
}

variable "inspect_min_likelihood" {
  description = "Minimum likelihood of the shared inspection template."
  type        = string
  default     = "POSSIBLE"
}
