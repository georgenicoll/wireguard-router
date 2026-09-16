locals {
  # Network tags are how GCP firewall rules select targets.
  network_tag = "${var.node_name}-wg"
}

resource "google_compute_address" "this" {
  name   = "${var.node_name}-ip"
  region = replace(var.zone, "/-[a-z]$/", "")
}

resource "google_compute_instance" "this" {
  name         = var.node_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [local.network_tag]
  labels       = var.tags

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size
      type  = "pd-standard"
    }
  }

  network_interface {
    network = var.network

    access_config {
      nat_ip = google_compute_address.this.address
    }
  }

  # Ubuntu's cloud images read cloud-init from the user-data metadata key.
  metadata = {
    user-data = var.user_data

    # The whole point of this host is routing other machines' traffic, so the
    # OS Login / project-wide SSH key paths are left off in favour of the
    # single key cloud-init installs.
    block-project-ssh-keys = "TRUE"
  }

  # Required for the instance to forward packets it did not originate.
  can_ip_forward = true

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}

resource "google_compute_firewall" "ssh" {
  name          = "${var.node_name}-allow-ssh"
  network       = var.network
  target_tags   = [local.network_tag]
  source_ranges = var.allowed_ssh_cidrs
  priority      = 1000

  allow {
    protocol = "tcp"
    ports    = [tostring(var.ssh_port)]
  }
}

resource "google_compute_firewall" "wireguard" {
  name          = "${var.node_name}-allow-wireguard"
  network       = var.network
  target_tags   = [local.network_tag]
  source_ranges = ["0.0.0.0/0"]
  priority      = 1000

  allow {
    protocol = "udp"
    ports    = [tostring(var.wireguard_port)]
  }
}

resource "google_compute_firewall" "icmp" {
  count         = var.allow_icmp ? 1 : 0
  name          = "${var.node_name}-allow-icmp"
  network       = var.network
  target_tags   = [local.network_tag]
  source_ranges = ["0.0.0.0/0"]
  priority      = 1000

  allow {
    protocol = "icmp"
  }
}
