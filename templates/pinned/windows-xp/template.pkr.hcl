# Windows XP Professional SP3 (x86)
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
  default = "local/iso/en_windows_xp_professional_with_service_pack_3_x86_cd_x14-80428.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:4cbecbdce1091e79445678595a1d9606651f2a81b1853d36877319102f4e9c2d6cc0ad3b8247b5ebd305571a39c2608d41459d8d782afc1b76a10d195de10a88"
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

  cpu_model = "core2duo"
  cpus      = 2
  memory    = 1024
  headless  = var.headless

  machine_type   = "pc"
  net_device     = "rtl8139"
  disk_interface = "ide"

  # For some reason, Windows XP fails to install on GitHub Actions with KVM enabled, so force TCG
  qemuargs = [
    ["-machine", "accel=tcg"],
    ["-global", "rtl8139.rombar=0"],
    ["-serial", "stdio"],
  ]

  floppy_files = ["${path.root}/floppy/winnt.sif", "${path.root}/floppy/setup.cmd"]
  cd_files = [
    "${path.root}/cd/setup-ssh.cmd",
    "${path.cwd}/local/misc/setupssh-7.3p1-2-cygwin252.exe",
  ]
  cd_label = "SSH"

  boot_command = [
    "<enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1>",
  ]
  boot_wait = "1s"

  communicator = "ssh"
  ssh_username = "Administrator"
  ssh_password = "rotartsinimda"
  ssh_timeout  = "2h"

  shutdown_command = "cmd /c shutdown -s -t 60 -f"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]
}
