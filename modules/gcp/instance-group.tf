# 5. Managed Instance Group for Auto-Healing Cluster Management
resource "google_compute_region_instance_group_manager" "hpc_group" {
  provider           = google-beta
  name               = "hpc-manager"
  region             = var.region
  base_instance_name = var.instance_name_prefix
  target_size        = var.instance_count
  
  distribution_policy_zones        = local.supported_zones
  distribution_policy_target_shape = "ANY"

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "NONE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 0
    max_unavailable_fixed        = length(local.supported_zones)
  }

  # Ensure the health of the instances in the cluster
  auto_healing_policies {
    health_check      = google_compute_health_check.hpc_health.id
    initial_delay_sec = 300
  }

  instance_lifecycle_policy {
    force_update_on_repair    = "YES"
    default_action_on_failure = "REPAIR"
    
    on_repair {
      allow_changing_zone = "YES"
    }
  }
}
