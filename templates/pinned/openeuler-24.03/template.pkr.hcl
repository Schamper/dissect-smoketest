# openEuler 24.03 LTS
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
  default = "https://mirrors.xtom.de/openeuler/openEuler-24.03-LTS-SP3/ISO/x86_64/openEuler-24.03-LTS-SP3-netinst-x86_64-dvd.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:808aa41bb0b25bb56768c550625bec9e4982094b8d4024be64fa0c6517e22900"
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

  machine_type      = "q35"
  net_device        = "virtio-net"
  disk_interface    = "virtio"
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  http_directory = "${path.root}/kickstart"

  boot_command = [
    "<up><wait>",
    "e<wait>",
    "<down><down><end>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>",
  ]
  boot_key_interval = "10ms"
  boot_wait         = "5s"

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
