# Proxmox VE (LVM-thin on ext4)
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

variable "iso_url" {
  type    = string
  default = "https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "32G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 4096
  headless  = var.headless

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  cd_files = ["${path.root}/ai/answer.toml"]
  cd_label = "PROXMOX-AIS"

  boot_command = [
    "e<wait>",
    "<down><down><down><end> proxmox-start-auto-installer<wait>",
    "<leftCtrlOn>x<leftCtrlOff><wait1m>",
    "proxmox-fetch-answer partition PROXMOX-AIS >/run/automatic-installer-answers<enter><wait>",
    "exit<enter>",
  ]
  boot_key_interval = "10ms"
  boot_wait         = "5s"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "1h"

  shutdown_command = "poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = [
      "mkdir -p /etc/dissect-smoketest",
      "printf 'template=proxmox-9\\nlifecycle=pinned\\n' > /etc/dissect-smoketest/provisioned",
    ]
  }
}
