output "project_a_id" {
  value       = google_project.project_a.project_id
  description = "The ID of Project A (Data Project)"
}

output "project_b_id" {
  value       = google_project.project_b.project_id
  description = "The ID of Project B (DMZ Project)"
}

output "service_account_email" {
  value       = google_service_account.test_sa.email
  description = "The email address of the test Service Account"
}

output "folder_id" {
  value       = local.folder_id
  description = "The folder ID (either created or existing)"
}

output "policy_id" {
  value       = local.policy_id
  description = "The Access Context Manager Policy ID (either created or existing)"
}
