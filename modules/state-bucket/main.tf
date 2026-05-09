terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_storage_bucket" "tfstate" {
  name                        = "blueprint-tfstate-${data.google_project.this.number}"
  project                     = var.project_id
  location                    = "US"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

output "bucket_name" {
  value = google_storage_bucket.tfstate.name
}
