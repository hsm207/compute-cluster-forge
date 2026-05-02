variable "project_id" {
  description = "The GCP Project ID where the cluster will be forged."
  type        = string

  validation {
    # Enforces GCP Project ID naming conventions:
    # 1. 6-30 characters long
    # 2. Starts with a lowercase letter
    # 3. Contains only lowercase letters, numbers, and hyphens
    # 4. Ends with a lowercase letter or number
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid GCP Project ID (6-30 chars, lowercase letters, numbers, and hyphens only)."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the GCS bucket name."
  type        = string
  default     = "hpc-data"
}

variable "region" {
  description = "The GCP region to deploy resources to."
  type        = string
  default     = "us-central1"
}


variable "zone" {
  description = "The specific GCP zone for the instances."
  type        = string
  default     = "us-central1-c"
}

variable "machine_type" {
  description = "The machine type for the compute instances (e.g., c2-standard-4)."
  type        = string
  default     = "n2-standard-2"
}

variable "gpu_type" {
  description = "The type of GPU to attach to the instances (e.g., nvidia-tesla-t4)."
  type        = string
  default     = null
}

variable "gpu_count" {
  description = "The number of GPUs to attach to each instance."
  type        = number
  default     = 0
}

variable "instance_count" {
  description = "The target number of instances in the managed instance group."
  type        = number
  default     = 1
}

variable "boot_disk_size" {
  description = "The size of the boot disk in GB."
  type        = number
  default     = 100
}

variable "boot_image" {
  description = "The OS image to use for the boot disk (e.g., debian-cloud/debian-11)."
  type        = string
  default     = "debian-cloud/debian-11"
}

variable "allowed_ports" {
  description = "List of TCP ports to allow via the IAP firewall."
  type        = list(string)
  default     = ["22", "8888"]
}

variable "instance_name_prefix" {
  description = "Base name for created GCP instances in the managed instance group."
  type        = string
  default     = "hpc-node"
}

variable "instance_tag" {
  description = "Network tag applied to the HPC instances and firewall rules."
  type        = string
  default     = "hpc-node"
}

variable "active_features" {
  description = "List of software features to enable (e.g., ['ollama', 'gemma4'])."
  type        = list(string)
  default     = []
}

variable "gcp_user" {
  description = "The primary GCP user account for the cluster (used for home directories)."
  type        = string
  default     = "hpc-user"
}
