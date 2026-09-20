locals {
  base_packages = [
    "wireguard",
    "wireguard-tools",
    "curl",
    "ca-certificates",
    "iptables",
    "jq",
    "ufw",
    "fail2ban",
    "unattended-upgrades",
    "qrencode",
  ]

  packages = distinct(concat(local.base_packages, var.extra_packages))

  # Server-side WireGuard interface definition.
  wireguard_config = templatefile("${path.module}/templates/wg.conf.tftpl", {
    address     = var.wireguard_address
    address_v6  = var.wireguard_address_v6
    listen_port = var.wireguard_port
    private_key = var.wireguard_private_key
    mtu         = var.wireguard_mtu
    nat         = var.wireguard_nat
    peers       = var.wireguard_peers
    interface   = var.wireguard_interface
  })

  # Helper that applies forwarding/NAT rules against whichever interface
  # happens to carry the default route. Detecting this at runtime is what lets
  # the identical config work on Linode (eth0), AWS (enX0), GCP (ens4), etc.
  wg_nat_script = templatefile("${path.module}/templates/wg-nat.sh.tftpl", {})

  dynu_script = templatefile("${path.module}/templates/dynu-update.sh.tftpl", {
    dynu_hostname = var.dynu_hostname
  })

  # The credentials land in a shell-sourced env file inside single quotes, so a
  # literal quote in either value has to be escaped the POSIX way ('\'').
  dynu_api_key_sh  = replace(var.dynu_api_key, "'", "'\\''")
  dynu_username_sh = replace(var.dynu_username, "'", "'\\''")
  dynu_password_sh = replace(var.dynu_password, "'", "'\\''")

  # Login banner: the shared "monkeynuthead" part comes from the ascii
  # submodule (github.com/georgenicoll/ascii); "Router" is specific to this
  # project, so it stays local (templates/router.txt) rather than going into
  # the shared submodule - same split as wireguard-ap's AP banner.
  banner = "${file("${path.module}/ascii/monkeynuthead.txt")}${file("${path.module}/templates/router.txt")}"

  motd = templatefile("${path.module}/templates/motd.tftpl", {
    banner            = local.banner
    wireguard_address = var.wireguard_address
    peers             = var.wireguard_peers
  })

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    node_name         = var.node_name
    dynu_hostname     = var.dynu_hostname
    timezone          = var.timezone
    admin_username    = var.admin_username
    ssh_public_keys   = [for k in var.ssh_public_keys : trimspace(k)]
    ssh_port          = var.ssh_port
    allowed_ssh_cidrs = var.allowed_ssh_cidrs
    packages          = local.packages

    wireguard_interface  = var.wireguard_interface
    wireguard_port       = var.wireguard_port
    wireguard_config_b64 = base64encode(local.wireguard_config)
    wg_nat_script_b64    = base64encode(local.wg_nat_script)

    dynu_script_b64      = base64encode(local.dynu_script)
    dynu_api_key_sh      = local.dynu_api_key_sh
    dynu_username_sh     = local.dynu_username_sh
    dynu_password_sh     = local.dynu_password_sh
    dynu_update_interval = var.dynu_update_interval

    motd_b64 = base64encode(local.motd)
  })
}
