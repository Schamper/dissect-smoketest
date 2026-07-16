# Oracle Solaris 11.4 stock image
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
  default = "local/iso/sol-11_4-ai-x86.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:e3a29507e583acbc0b912f371c8f328fea7cb6257d587cbc0a651477a52b0a29"
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
  disk_size          = "32G"
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

  http_directory = "${path.root}/ai"

  boot_command = [
    "e<wait>",
    "<down><down><down><down><down><wait>",
    "<end><wait>",
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><wait>",
    "false<wait>",
    "<f10><wait>",
    "<wait10><wait10><wait10><wait10><wait10><wait10>",
    "<wait10><wait10><wait10><wait10><wait10><wait10>",
    "root<enter><wait><wait>",
    "solaris<enter><wait10>>",

    "<enter>while (true);",
    "do test -f /a/etc/ssh/sshd_config && perl -pi -e 's/PermitRootLogin no/PermitRootLogin yes/' /a/etc/ssh/sshd_config && break;",
    "sleep 10;",
    "done &<enter><wait>",

    "curl http://{{ .HTTPIP }}:{{ .HTTPPort }}/ai.xml -o /system/volatile/ai.xml<enter><wait>",
    "mkdir /system/volatile/profile<enter><wait>",
    "curl http://{{ .HTTPIP }}:{{ .HTTPPort }}/profile.xml -o /system/volatile/profile/profile.xml<enter><wait>",
    "svcadm enable svc:/application/auto-installer:default<enter><wait>",
    "<enter><wait10><wait><wait>",
    "<enter><wait>",
    "tail -f /system/volatile/install_log<enter><wait>"
  ]
  boot_key_interval = "10ms"
  boot_wait         = "5s"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "2h"

  shutdown_command = "/usr/sbin/poweroff"
  shutdown_timeout = "5m"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]
}
