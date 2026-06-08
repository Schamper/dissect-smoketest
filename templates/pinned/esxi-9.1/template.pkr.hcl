# ESXi 9.1 stock image
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
  default = "local/iso/VMware-VMvisor-Installer-9.1.0.0100.25433460.x86_64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:53be2f026b1b887f96fd43c8b0b08a23507a13f7f9a5d5243d5167fc86a963cf49bdf11de6e6ea3bf7a6e194341a7373bfe5e150cb08e4e0b137d68f383ad73e"
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
  memory    = 8192
  headless  = var.headless

  machine_type      = "q35"
  net_device        = "vmxnet3"
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-boot", "once=d"],
    ["-device", "ich9-ahci,id=sata"],
    ["-device", "ide-hd,drive=sata-disk,bus=sata.0"],
    ["-drive", "file=${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk,if=none,id=sata-disk,cache=writeback,discard=unmap,detect-zeroes=on,format=qcow2"],
    ["-drive", "file=${path.cwd}/${var.iso_url},media=cdrom"],
    ["-drive", "file=${var.efi_firmware_code},if=pflash,unit=0,format=raw,readonly=on"],
    ["-drive", "file=${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/efivars.fd,if=pflash,unit=1,format=raw"],
    ["-serial", "stdio"],
  ]

  http_directory = "${path.root}/kickstart"

  boot_command = [
    "O<wait>",
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs>",
    "ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg timeoutCS=99999 com1_Port=0x3f8 tty2Port=com1",
    "<enter>",
  ]
  boot_key_interval = "10ms"
  boot_wait         = "4s"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "1h"

  shutdown_command = "poweroff -d 60"

  shutdown_timeout = "30m"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]
}
