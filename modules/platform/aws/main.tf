data "aws_vpc" "selected" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.selected[0].id
}

data "aws_subnets" "available" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Random rather than sort(...)[0]: EC2 capacity shortages are per-AZ and
# transient, so a fixed pick can keep hitting the same short-on-capacity AZ.
# The result is stored in state and stays fixed across plain re-applies; to
# retry with a different AZ after an InsufficientInstanceCapacity error,
# destroy and re-apply.
resource "random_shuffle" "subnet" {
  count        = var.subnet_id == "" ? 1 : 0
  input        = data.aws_subnets.available[0].ids
  result_count = 1
}

locals {
  subnet_id = var.subnet_id != "" ? var.subnet_id : random_shuffle.subnet[0].result[0]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-${var.ubuntu_release}-${var.architecture}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "this" {
  name        = "${var.node_name}-sg"
  description = "WireGuard router: SSH and WireGuard inbound only"
  vpc_id      = local.vpc_id

  ingress {
    description = "ssh"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description      = "wireguard"
    from_port        = var.wireguard_port
    to_port          = var.wireguard_port
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  dynamic "ingress" {
    for_each = var.allow_icmp ? [1] : []
    content {
      description = "icmp echo"
      from_port   = 8
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description      = "all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, { Name = "${var.node_name}-sg" })
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  associate_public_ip_address = true

  # Peers' traffic is NATed on this host, so it must be allowed to forward
  # packets whose source address is not its own.
  source_dest_check = false

  # EC2 has the same tight 16384-byte decoded limit as Linode, and a couple of
  # site-to-site peers clears it easily. user_data_base64 (rather than plain
  # user_data, which the provider would base64-encode as-is) lets us hand over
  # pre-gzipped bytes; cloud-init auto-detects and decompresses them.
  user_data_base64            = base64gzip(var.user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.node_name })

  lifecycle {
    # ami: see the AMI data source above. subnet_id: a later -replace of
    # random_shuffle.subnet (to retry a different AZ) must not move an
    # instance that's already running.
    ignore_changes = [ami, subnet_id]
  }
}
