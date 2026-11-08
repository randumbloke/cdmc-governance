tier            = "nonprod"
tf_state_bucket = "tfstate-pltfrm-ngnrng"

# Business domains served by this tier's hub; one set of state bucket folders per environment.
domain_businesses = ["customer", "accounts"]

# Phase 2 (design §6.17): grants for the classifier's aspect type and state bucket folders.
classifier_enabled = false
