# openSUSE Leap 16.1 Minimal-VM cloud image
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific Leap 16 build. To bump:
# 1. Pick a build from https://download.opensuse.org/distribution/leap/*/appliances/
# 2. Copy the matching SHA256 from <image>.sha256
variable "iso_url" {
  type    = string
  default = "https://download.opensuse.org/distribution/leap/16.1/appliances/Leap-16.0-Minimal-VM.x86_64-Cloud.qcow2"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:c10e8d2693b01b3c8059b94086e044e6c77313a798499fd3c5d05c3387f6f547"
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
