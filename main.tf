provider "google" {
  project = "project"
  region  = "us-central1"
}

variable "gce_ssh_user" {
  default = "testuser"
}

variable "gce_ssh_pub_key_file" {
  default = "key/testuser/pub.key"
}

resource "google_compute_instance_template" "app" {
  name        = "app-template"
  description = "This template is used to create app server instances."

  tags = ["http-server", "https-server"]

  labels = {
    environment = "test"
    app         = "app"
  }

  instance_description = "app server instances"
  machine_type         = "n1-standard-1"

  // Create a new boot disk from an image
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-1604-lts"
    auto_delete  = false
    boot         = true
    disk_type    = "pd-ssd"
    disk_size_gb = 50
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  metadata {
    ssh-keys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}

resource "google_compute_instance_group_manager" "appserver" {
  name               = "app-server-group"
  base_instance_name = "app-server"
  instance_template  = "${google_compute_instance_template.app.self_link}"
  update_strategy    = "NONE"
  zone               = "us-central1-b"
  target_size        = 1

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_http_health_check" "app" {
  name               = "app-health-check"
  request_path       = "/"
  check_interval_sec = 30
  timeout_sec        = 10
}

resource "google_compute_backend_service" "app" {
  name        = "app-backend"
  description = "app server backend"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 300
  enable_cdn  = false

  backend {
    group = "${google_compute_instance_group_manager.appserver.instance_group}"
  }

  health_checks = ["${google_compute_http_health_check.app.self_link}"]
}

resource "google_compute_url_map" "default" {
  name        = "loadbalancer"
  description = "URL Map Loadbalancer"

  default_service = "${google_compute_backend_service.app.self_link}"

  host_rule {
    hosts        = ["example.com", "www.example.com"]
    path_matcher = "apppath"
  }

  path_matcher {
    name            = "apppath"
    default_service = "${google_compute_backend_service.app.self_link}"

    path_rule {
      paths   = ["/*"]
      service = "${google_compute_backend_service.app.self_link}"
    }
  }
}

resource "google_compute_target_http_proxy" "default" {
  name        = "http-proxy"
  description = "HTTP Proxy for App"
  url_map     = "${google_compute_url_map.default.self_link}"
}

resource "google_compute_target_https_proxy" "default" {
  name             = "https-proxy"
  description      = "HTTPS Proxy for App"
  url_map          = "${google_compute_url_map.default.self_link}"
  ssl_certificates = ["${google_compute_ssl_certificate.default.self_link}"]
}

resource "google_compute_global_address" "default" {
  name = "static-ip"

  #  lifecycle {
  #    prevent_destroy = true
  #  }
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "http-forwarding-rule"
  target     = "${google_compute_target_http_proxy.default.self_link}"
  port_range = "80"
  ip_address = "${google_compute_global_address.default.self_link}"
}

resource "google_compute_global_forwarding_rule" "ssl-default" {
  name       = "https-forwarding-rule"
  target     = "${google_compute_target_https_proxy.default.self_link}"
  port_range = "443"
  ip_address = "${google_compute_global_address.default.self_link}"
}

resource "google_compute_ssl_certificate" "default" {
  name        = "ssl-certificate"
  description = "SSL Cert for example.com"
  private_key = "${file("key/ssl/private.key")}"
  certificate = "${file("key/ssl/certificate.crt")}"
}
