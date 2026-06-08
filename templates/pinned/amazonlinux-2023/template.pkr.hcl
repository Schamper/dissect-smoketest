# Amazon Linux 2023
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific Amazon Linux 2023 build. To bump:
# 1. Pick a build from https://cdn.amazonlinux.com/al2023/os-images/latest/
# 2. Copy the matching SHA256 from the SHA256SUMS file
variable "iso_url" {
  type    = string
  default = "https://cdn.amazonlinux.com/al2023/os-images/2023.12.20260710.0/kvm/al2023-kvm-2023.12.20260710.0-kernel-6.1-x86_64.xfs.gpt.qcow2"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:092002e43e67dcb2c2380778b64b0197ad3594935bd61709eae9557e3655c007"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_image         = true
  disk_size          = "32G"
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
