# Azure Linux 4.0 stock
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
  default = "https://aka.ms/azurelinux-4.0-x86_64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "d98f7d1ffaa916de7c9f66ffdadb150c174da691509e760835709ffa7829ca48"
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
  memory    = 2048
  headless  = var.headless

  machine_type      = "q35"
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  boot_command = [
    "install-azl<enter><wait>",
    "1<enter><wait30>",                                                         # Unencrypted disk
    "7<enter><wait>1<enter><wait>",                                             # Create user
    "3<enter><wait>user<enter><wait>",                                          # Username
    "5<enter><wait>password<enter><wait>password<enter><wait>yes<enter><wait>", # Password
    "c<enter><wait>b<enter><wait5m>",                                           # Start installation
    "<enter>",                                                                  # Exit
  ]
  boot_key_interval = "20ms"
  boot_wait         = "1m"

  communicator = "ssh"
  ssh_username = "user"
  ssh_password = "password"
  ssh_timeout  = "15m"

  shutdown_command = "echo 'password' | sudo -S poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = ["sudo cloud-init status --wait || true"]
  }
}
