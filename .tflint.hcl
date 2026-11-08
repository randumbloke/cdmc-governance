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
  version = "0.30.0" # VERIFY IN BUILD (no VA ID): ruleset version current at first run
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
