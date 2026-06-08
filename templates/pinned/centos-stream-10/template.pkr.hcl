# CentOS Stream 10 stock cloud image
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific CentOS Stream 10 build. To bump:
# 1. Pick a build from https://cloud.centos.org/centos/10-stream/x86_64/images/
# 2. Copy the matching SHA256 from the CHECKSUM file
variable "iso_url" {
  type    = string
  default = "https://cloud.centos.org/centos/10-stream/x86_64/images/CentOS-Stream-GenericCloud-10-20260622.0.x86_64.qcow2"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:508a48761d1a28c98046256e8f77b0ea34d751791a5629bb216743ef98526d0b"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_image         = true
  disk_size          = "10G"
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
