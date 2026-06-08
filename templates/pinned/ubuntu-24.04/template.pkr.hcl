# Ubuntu 24.04 LTS (Noble Numbat) stock cloud image
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific dated Noble release. To bump:
# 1. Pick a dated release from https://cloud-images.ubuntu.com/noble/
# 2. Copy the matching SHA256 from that release's SHA256SUMS file
variable "iso_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/20260615/noble-server-cloudimg-amd64.img"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:5fa5b05e5ec239858c4531485d6023b0896448c2df7c63b34f8dae6ea6051a44"
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
