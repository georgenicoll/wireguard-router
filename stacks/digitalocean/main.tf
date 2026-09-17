# Cloud-agnostic configuration: WireGuard, Dynu and host hardening. This block
# is identical in every stack.
module "node_config" {
  source = "../../modules/node-config"

  node_name = var.node_name
  timezone  = var.timezone

  admin_username    = var.admin_username
  ssh_public_keys   = var.ssh_public_keys
  ssh_port          = var.ssh_port
  allowed_ssh_cidrs = var.allowed_ssh_cidrs

  wireguard_interface   = var.wireguard_interface
  wireguard_port        = var.wireguard_port
  wireguard_address     = var.wireguard_address
  wireguard_address_v6  = var.wireguard_address_v6
  wireguard_private_key = var.wireguard_private_key
  wireguard_mtu         = var.wireguard_mtu
  wireguard_peers       = var.wireguard_peers
  wireguard_nat         = var.wireguard_nat

  dynu_hostname        = var.dynu_hostname
  dynu_api_key         = var.dynu_api_key
  dynu_username        = var.dynu_username
  dynu_password        = var.dynu_password
  dynu_update_interval = var.dynu_update_interval

  extra_packages = var.extra_packages
}

# The only provider-specific part: create a VM and open two ports.
module "server" {
  source = "../../modules/platform/digitalocean"

  node_name         = var.node_name
  user_data         = module.node_config.cloud_init
  ssh_port          = var.ssh_port
  wireguard_port    = var.wireguard_port
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  allow_icmp        = var.allow_icmp
  tags              = var.tags

  region       = var.region
  droplet_size = var.droplet_size
  image        = var.image
}
