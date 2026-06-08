# Windows 11 Professional - rolling
#
# Runs a complete Windows Update so the resulting image represents
# "freshly updated stable" at the moment of build.
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
    windows-update = {
      version = "~> 0.18"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "iso_url" {
  type    = string
  default = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:d9880aa30635de940f27bd2892727650dbc957a4c688d7c937f2ee8cda97a910eae43f034901a818519c55ddb11465b2ca68bbf780b170deb1b5ebef205ff6c0"
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
  disk_size          = "60G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 4
  memory    = 4096
  headless  = var.headless

  machine_type      = "q35"
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

  cd_files = ["${path.root}/autounattend/Autounattend.xml", "${path.root}/autounattend/setup-ssh.cmd", "${path.cwd}/local/misc/OpenSSH-Win64.msi"]
  cd_label = "cidata"

  boot_command = ["<return>", "<wait3>", "<return>", "<wait3>", "<return>"]
  boot_wait    = "2s"

  communicator = "ssh"
  ssh_username = "Administrator"
  ssh_password = "rotartsinimda"
  ssh_timeout  = "2h"

  shutdown_command = "shutdown /s /t 60 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "5m"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "windows-update" {
    search_criteria = "IsInstalled=0"
  }
}
