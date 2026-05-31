variable "org_id" {
  type        = string
  description = "Google Cloud Organization ID"
}

variable "billing_id" {
  type        = string
  description = "Billing Account ID"
}


variable "suffix" {
  type        = string
  description = "Dynamic suffix to prevent resource naming collisions"
}

variable "proj_a" {
  type        = string
  description = "ID of Project A (Data Project)"
}

variable "proj_b" {
  type        = string
  description = "ID of Project B (DMZ Project)"
}

variable "sa_name" {
  type        = string
  default     = "test-viewer-sa"
  description = "Service Account name for the third-party test identity"
}

variable "sa_email" {
  type        = string
  description = "Full email address of the test Service Account"
}

variable "enable_cross_perimeter_access" {
  type        = bool
  default     = false
  description = "Controls whether the ingress/egress rules are enabled for the perimeters"
}

variable "current_user" {
  type        = string
  description = "The email address of the active user or service account executing the tests"
}

variable "policy_id" {
  type        = string
  description = "The ID of the Access Context Manager policy to use (either scoped or unscoped)"
}

variable "billing_project" {
  type        = string
  description = "Persistent GCP project used for ACM billing override (avoids user_project_denied when temp projects are deleted)"
  default     = ""
}

