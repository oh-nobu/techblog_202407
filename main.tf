variable "project" {
  description = "The IP segment for the VPC"
  type        = string
}

variable "frontend_image_tag" {
  description = "The tag of frontend image"
  type        = string
}

variable "backend_image_tag" {
  description = "The tag of the backend image"
  type        = string
}

variable "doman_name" {
  description = "use domain name"
  type        = string
}

terraform {
  backend "gcs" {
    bucket = "ohashi-deploy-test-20240701_tfstate"
  }
}

provider "google" {
  project = var.project
  region  = "asia-northeast1"
}

provider "google-beta" {
  project = var.project
  region  = "asia-northeast1"
}

resource "google_artifact_registry_repository" "demo" {
  provider      = google-beta
  location      = "asia-northeast1"
  repository_id = "demo"
  format        = "DOCKER"
}

resource "google_compute_network" "demo" {
  name                    = "demo"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "demo" {
  name          = "demo"
  ip_cidr_range = "10.0.0.0/24"
  region        = "asia-northeast1"
  network       = google_compute_network.demo.id
}

resource "google_compute_router" "demo" {
  name    = "demo"
  network = google_compute_network.demo.id
  region  = "asia-northeast1"
}

resource "google_compute_router_nat" "demo" {
  name   = "demo"
  router = google_compute_router.demo.name
  region = "asia-northeast1"

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "null_resource" "frontend" {
  triggers = {
    image_version = "${var.frontend_image_tag}"
  }

  provisioner "local-exec" {
    command = <<EOT
      docker build -t asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/frontend:${var.frontend_image_tag} \
      -f ./frontend/Dockerfile ./frontend/
      docker push asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/frontend:${var.frontend_image_tag}
    EOT
  }
}

resource "null_resource" "backend" {
  triggers = {
    image_version = "${var.backend_image_tag}"
  }

  provisioner "local-exec" {
    command = <<EOT
      docker build -t asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/backend:${var.backend_image_tag} \
      -f ./backend/Dockerfile ./backend
      docker push asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/backend:${var.backend_image_tag}
    EOT
  }
}

resource "google_service_account" "demo" {
  account_id = "demo-account"
}

resource "google_project_iam_member" "demo" {
  project = var.project
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.demo.email}"
}

resource "google_cloud_run_v2_service" "frontend" {
  name     = "frontend"
  location = "asia-northeast1"

  template {
    service_account = google_service_account.demo.email
    containers {
      image = "asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/frontend:${var.frontend_image_tag}"
      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }

      env {
        name  = "API_URL"
        value = google_cloud_run_v2_service.backend.uri
      }
    }

    vpc_access {
      egress = "ALL_TRAFFIC"
      network_interfaces {
        network    = google_compute_network.demo.name
        subnetwork = google_compute_subnetwork.demo.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [null_resource.frontend]
}

resource "google_cloud_run_service_iam_policy" "frontend" {
  location    = google_cloud_run_v2_service.frontend.location
  service     = google_cloud_run_v2_service.frontend.name
  policy_data = data.google_iam_policy.frontend.policy_data
}

data "google_iam_policy" "frontend" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "backend"
  location = "asia-northeast1"

  template {
    service_account = google_service_account.demo.email
    containers {
      image = "asia-northeast1-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.demo.repository_id}/backend:${var.backend_image_tag}"
    }

    vpc_access {
      egress = "ALL_TRAFFIC"
      network_interfaces {
        network    = google_compute_network.demo.name
        subnetwork = google_compute_subnetwork.demo.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [null_resource.backend]
}

resource "google_cloud_run_service_iam_policy" "backend" {
  location    = google_cloud_run_v2_service.backend.location
  service     = google_cloud_run_v2_service.backend.name
  policy_data = data.google_iam_policy.backend.policy_data
}

data "google_iam_policy" "backend" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_compute_region_network_endpoint_group" "frontend" {
  name                  = "frontend"
  network_endpoint_type = "SERVERLESS"
  region                = "asia-northeast1"
  cloud_run {
    service = google_cloud_run_v2_service.frontend.name
  }
}

resource "google_compute_region_network_endpoint_group" "backend" {
  name                  = "backend"
  network_endpoint_type = "SERVERLESS"
  region                = "asia-northeast1"
  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }
}

resource "google_compute_backend_service" "frontend" {
  name                  = "frontend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"
  backend {
    group = google_compute_region_network_endpoint_group.frontend.id
  }

  lifecycle {
    ignore_changes = [
      iap,
    ]
  }
}

resource "google_compute_backend_service" "backend" {
  name                  = "backend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"
  backend {
    group = google_compute_region_network_endpoint_group.backend.id
  }
}

resource "google_compute_url_map" "demo" {
  name = "demo"

  default_service = google_compute_backend_service.frontend.id
}

resource "google_compute_global_address" "demo" {
  name = "demo"
}

resource "google_compute_managed_ssl_certificate" "demo" {
  provider = google-beta

  name = "demo"
  managed {
    domains = [
      "${var.doman_name}",
    ]
  }
}

resource "google_compute_target_https_proxy" "demo" {
  name             = "demo"
  url_map          = google_compute_url_map.demo.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.demo.id]
}

resource "google_compute_global_forwarding_rule" "demo" {
  name       = "demo"
  target     = google_compute_target_https_proxy.demo.self_link
  port_range = "443"
  ip_address = google_compute_global_address.demo.address
}
