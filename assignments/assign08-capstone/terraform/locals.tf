# =============================================================================
# Local Values
# =============================================================================
# Locals let us define computed values used throughout the project.
# We use the prefix here so every resource name starts with "chikwex-".

locals {
  prefix = var.prefix

  # Naming convention: chikwex-<environment>-<resource>
  production_name      = "${local.prefix}-production"
  staging_name         = "${local.prefix}-staging"
  shared_services_name = "${local.prefix}-shared-services"
}
