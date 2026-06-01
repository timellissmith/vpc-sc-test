terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

provider "google" {
  # Default provider (used for Folder, Projects, Billing, APIs)
}

provider "google" {
  alias                 = "acm"
  user_project_override = true
  billing_project       = var.billing_project != "" ? var.billing_project : var.proj_b
}

# ------------------------------------------------------------------------------
# 1. Folder Setup (Always created fresh on each run)
# ------------------------------------------------------------------------------
resource "google_folder" "sandbox" {
  display_name        = "VPC-SC-Sandbox-${var.suffix}"
  parent              = "organizations/${var.org_id}"
  deletion_protection = false
}

locals {
  folder_id   = google_folder.sandbox.id
  folder_name = google_folder.sandbox.name
}

# ------------------------------------------------------------------------------
# 2. Access Policy Setup (Using existing organization default policy)
# ------------------------------------------------------------------------------
resource "time_sleep" "wait_for_project_b" {
  create_duration = "45s"

  depends_on = [
    google_project_service.project_a_services,
    google_project_service.project_b_services
  ]
}

locals {
  policy_id = var.policy_id
}


# ------------------------------------------------------------------------------
# 3. Projects Creation & Billing Association
# ------------------------------------------------------------------------------
resource "google_project" "project_a" {
  name            = var.proj_a
  project_id      = var.proj_a
  folder_id       = local.folder_id
  deletion_policy = "DELETE"
}

resource "google_project" "project_b" {
  name            = var.proj_b
  project_id      = var.proj_b
  folder_id       = local.folder_id
  deletion_policy = "DELETE"
}

resource "google_billing_project_info" "project_a_billing" {
  project         = google_project.project_a.project_id
  billing_account = var.billing_id
}

resource "google_billing_project_info" "project_b_billing" {
  project         = google_project.project_b.project_id
  billing_account = var.billing_id
}

# ------------------------------------------------------------------------------
# 4. Enable Google Cloud Services/APIs
# ------------------------------------------------------------------------------
locals {
  apis = [
    "bigquery.googleapis.com",
    "analyticshub.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com"
  ]
}

resource "google_project_service" "project_a_services" {
  for_each           = toset(local.apis)
  project            = google_project.project_a.project_id
  service            = each.key
  disable_on_destroy = false

  depends_on = [
    google_billing_project_info.project_a_billing
  ]
}

resource "google_project_service" "project_b_services" {
  for_each           = toset(local.apis)
  project            = google_project.project_b.project_id
  service            = each.key
  disable_on_destroy = false

  depends_on = [
    google_billing_project_info.project_b_billing
  ]
}

# ------------------------------------------------------------------------------
# 5. BigQuery Datasets
# ------------------------------------------------------------------------------
resource "google_bigquery_dataset" "data_dataset" {
  project                    = google_project.project_a.project_id
  dataset_id                 = "data_dataset"
  location                   = "US"
  delete_contents_on_destroy = true

  depends_on = [google_project_service.project_a_services]
}

resource "google_bigquery_dataset" "view_dataset" {
  project                    = google_project.project_b.project_id
  dataset_id                 = "view_dataset"
  location                   = "US"
  delete_contents_on_destroy = true

  depends_on = [google_project_service.project_b_services]
}

# ------------------------------------------------------------------------------
# 6. BigQuery Table and Test Data (Project A)
# ------------------------------------------------------------------------------
resource "google_bigquery_table" "my_table" {
  project             = google_project.project_a.project_id
  dataset_id          = google_bigquery_dataset.data_dataset.dataset_id
  table_id            = "my_table"
  deletion_protection = false

  schema = <<EOF
[
  {
    "name": "data_field",
    "type": "STRING",
    "mode": "NULLABLE"
  }
]
EOF
}

# Insert top secret test data row using a BigQuery query job
resource "google_bigquery_job" "populate_data" {
  project  = google_project.project_a.project_id
  job_id   = "populate_data_${var.suffix}"
  location = "US"

  query {
    query          = "INSERT INTO `${google_project.project_a.project_id}.${google_bigquery_dataset.data_dataset.dataset_id}.${google_bigquery_table.my_table.table_id}` (data_field) VALUES ('Top Secret Project A Data')"
    use_legacy_sql = false
    create_disposition = ""
    write_disposition  = ""
  }

  depends_on = [
    google_bigquery_table.my_table,
    google_project_service.project_a_services
  ]
}

# ------------------------------------------------------------------------------
# 7. BigQuery View (Project B / DMZ)
# ------------------------------------------------------------------------------
resource "google_bigquery_table" "my_view" {
  project             = google_project.project_b.project_id
  dataset_id          = google_bigquery_dataset.view_dataset.dataset_id
  table_id            = "my_view"
  deletion_protection = false

  view {
    query          = "SELECT * FROM `${google_project.project_a.project_id}.${google_bigquery_dataset.data_dataset.dataset_id}.${google_bigquery_table.my_table.table_id}`"
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.my_table,
    google_project_service.project_b_services
  ]
}

# ------------------------------------------------------------------------------
# 8. Authorize Project B's view in Project A's dataset
# ------------------------------------------------------------------------------
resource "google_bigquery_dataset_access" "authorized_view" {
  project    = google_project.project_a.project_id
  dataset_id = google_bigquery_dataset.data_dataset.dataset_id

  view {
    project_id = google_project.project_b.project_id
    dataset_id = google_bigquery_dataset.view_dataset.dataset_id
    table_id   = google_bigquery_table.my_view.table_id
  }
}

# ------------------------------------------------------------------------------
# 9. BigQuery Analytics Hub Configuration (DMZ Sharing)
# ------------------------------------------------------------------------------
resource "google_bigquery_analytics_hub_data_exchange" "dmz_exchange" {
  provider         = google.acm
  project          = google_project.project_b.project_id
  data_exchange_id = "dmz_exchange_${var.suffix}"
  location         = "US"
  display_name     = "DMZ Cross Perimeter Data Exchange"

  depends_on = [
    time_sleep.wait_for_project_b
  ]
}

resource "google_bigquery_analytics_hub_listing" "dmz_listing" {
  provider         = google.acm
  project          = google_project.project_b.project_id
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.dmz_exchange.data_exchange_id
  listing_id       = "dmz_listing_${var.suffix}"
  location         = "US"
  display_name     = "DMZ Test View Listing"

  bigquery_dataset {
    dataset = "projects/${google_project.project_b.project_id}/datasets/${google_bigquery_dataset.view_dataset.dataset_id}"
  }
}

resource "google_bigquery_analytics_hub_listing_subscription" "dmz_subscription" {
  provider         = google.acm
  project          = google_project.project_b.project_id
  location         = "US"
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.dmz_exchange.data_exchange_id
  listing_id       = google_bigquery_analytics_hub_listing.dmz_listing.listing_id

  destination_dataset {
    dataset_reference {
      dataset_id = "linked_dataset"
      project_id = google_project.project_b.project_id
    }
    location = "US"
  }
}

# ------------------------------------------------------------------------------
# 10. Third-Party Identity IAM Configuration
# ------------------------------------------------------------------------------
resource "google_service_account" "test_sa" {
  project      = google_project.project_b.project_id
  account_id   = var.sa_name
  display_name = "Test Third Party"

  depends_on = [google_project_service.project_b_services]
}

resource "google_project_iam_member" "bq_job_user" {
  project = google_project.project_b.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.test_sa.email}"
}

resource "google_project_iam_member" "bq_data_viewer" {
  project = google_project.project_b.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.test_sa.email}"
}

locals {
  is_service_account = length(regexall("gserviceaccount\\.com$", var.current_user)) > 0
  current_member     = local.is_service_account ? "serviceAccount:${var.current_user}" : "user:${var.current_user}"
}

resource "google_service_account_iam_member" "token_creator" {
  service_account_id = google_service_account.test_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.current_member
}

# ------------------------------------------------------------------------------
# 11. VPC Service Controls (Service Perimeters)
# ------------------------------------------------------------------------------
resource "google_access_context_manager_service_perimeter" "perimeter_a" {
  provider = google.acm
  parent   = "accessPolicies/${local.policy_id}"
  name     = "accessPolicies/${local.policy_id}/servicePerimeters/perimeter_a_${var.suffix}"
  title    = "Perimeter A ${var.suffix}"

  depends_on = [
    google_project_service.project_a_services,
    google_project_service.project_b_services
  ]

  status {
    resources           = ["projects/${google_project.project_a.number}"]
    restricted_services = [
      "bigquery.googleapis.com",
      "analyticshub.googleapis.com"
    ]

    # Baseline Ingress policy: Allows runner to manage inside Perimeter A
    ingress_policies {
      ingress_from {
        identities = [local.current_member]
        sources {
          access_level = "*"
        }
      }
      ingress_to {
        operations {
          service_name = "*"
        }
        resources = ["projects/${google_project.project_a.number}"]
      }
    }

    # Ingress rule: Allow cross-perimeter access ONLY from Project B
    dynamic "ingress_policies" {
      for_each = var.enable_cross_perimeter_access ? [1] : []
      content {
        ingress_from {
          identity_type = "ANY_IDENTITY"
          sources {
            resource = "projects/${google_project.project_b.number}"
          }
        }
        ingress_to {
          operations {
            service_name = "*"
          }
          resources = ["projects/${google_project.project_a.number}"]
        }
      }
    }

    # Egress rule: Allow cross-perimeter egress ONLY to Project B
    dynamic "egress_policies" {
      for_each = var.enable_cross_perimeter_access ? [1] : []
      content {
        egress_from {
          identity_type = "ANY_IDENTITY"
        }
        egress_to {
          operations {
            service_name = "*"
          }
          resources = ["projects/${google_project.project_b.number}"]
        }
      }
    }
  }
}

resource "google_access_context_manager_service_perimeter" "perimeter_b" {
  provider = google.acm
  parent   = "accessPolicies/${local.policy_id}"
  name     = "accessPolicies/${local.policy_id}/servicePerimeters/perimeter_b_${var.suffix}"
  title    = "Perimeter B ${var.suffix}"

  depends_on = [
    google_project_service.project_a_services,
    google_project_service.project_b_services
  ]

  status {
    resources           = ["projects/${google_project.project_b.number}"]
    restricted_services = [
      "bigquery.googleapis.com",
      "analyticshub.googleapis.com"
    ]

    # Baseline Ingress policy: Allows test identity and runner to query/manage inside Perimeter B
    ingress_policies {
      ingress_from {
        identities = [
          "serviceAccount:${google_service_account.test_sa.email}",
          local.current_member
        ]
        sources {
          access_level = "*"
        }
      }
      ingress_to {
        operations {
          service_name = "*"
        }
        resources = ["projects/${google_project.project_b.number}"]
      }
    }

    # Egress rule: Service Account can write/query to Project A if cross-perimeter is enabled
    dynamic "egress_policies" {
      for_each = var.enable_cross_perimeter_access ? [1] : []
      content {
        egress_from {
          identity_type = "ANY_IDENTITY"
        }
        egress_to {
          operations {
            service_name = "*"
          }
          resources = ["projects/${google_project.project_a.number}"]
        }
      }
    }
  }
}
