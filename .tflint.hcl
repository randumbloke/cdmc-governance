# tflint with the Google ruleset (design §6.3).
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_unused_declarations" {
  enabled = false
}

# Decision P6-28: a branch ref (?ref=main) is allowed on cross-repository module sources.
rule "terraform_module_pinned_source" {
  enabled = false
}
