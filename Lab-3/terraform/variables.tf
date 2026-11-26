variable "replicas" {
  description = "Number of taskboard containers to run"
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 5
    error_message = "replicas must be between 1 and 5."
  }
}

variable "base_port" {
  description = "Host port for the first replica; replica N gets base_port + N - 1"
  type        = number
  default     = 8100
}

variable "feature_priority_tasks" {
  description = "Turn on the priority_tasks feature flag in every replica"
  type        = bool
  default     = false
}

variable "docker_host" {
  description = "Docker daemon address; null uses DOCKER_HOST or the default socket"
  type        = string
  default     = null
}
