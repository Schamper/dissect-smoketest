# XenServer 8 stock image
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
  default = "https://downloads.xenserver.com/xenserver/2026-06-03.1330/XenServer8_2026-06-03.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:52f392cd5edc936f98f106b959b085bda5b1476fb6bed501da9be35bbd088d06"
}

# UEFI firmware (OVMF).
variable "efi_firmware_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "64G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 4096
  headless  = var.headless

  machine_type      = "pc"
  net_device        = "e1000"
  disk_interface    = "ide"
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-global", "e1000.rombar=0"],
    ["-serial", "stdio"],
  ]

  http_port_min  = 8169
  http_port_max  = 8169
  http_directory = "${path.root}/answerfile"

  boot_command      = ["e", "<down>", "<down>", "<down><down><left>", " answerfile=http://{{.HTTPIP}}:{{.HTTPPort}}/answerfile.xml <f10>"]
  boot_key_interval = "10ms"
  boot_wait         = "2s"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "30m"

  shutdown_command = "poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]
}
