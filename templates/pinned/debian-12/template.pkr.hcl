# Debian 12 (Bookworm) stock cloud image
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific dated Debian release. To bump:
# 1. Pick a dated release from https://cloud.debian.org/images/cloud/bookworm/
# 2. Copy the matching SHA512 from that release's SHA512SUMS file
variable "iso_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/20260601-2496/debian-12-genericcloud-amd64-20260601-2496.qcow2"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:ff1c5b86c680bf29fb65a485296f45da744c9f636cb3c3ecc573b7c51ff88797ef207119e40f07ae9428b9bb539d57b490cdb2beecdfbac25dc95163e1418936"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_image         = true
  disk_size          = "8G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 2048
  headless  = var.headless

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  cd_files = ["${path.root}/cloud-init/user-data", "${path.root}/cloud-init/meta-data"]
  cd_label = "cidata"

  boot_wait = "5s"

  communicator = "ssh"
  ssh_username = "user"
  ssh_password = "password"
  ssh_timeout  = "15m"

  shutdown_command = "sudo poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = ["sudo cloud-init status --wait || true"]
  }
}
