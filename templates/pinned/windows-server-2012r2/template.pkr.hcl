# Windows Server 2012 R2 Standard (x64)
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
  default = "http://download.microsoft.com/download/6/2/A/62A76ABB-9990-4EFC-A4FE-C7D698DAEB96/9600.16384.WINBLUE_RTM.130821-1623_X64FRE_SERVER_EVAL_EN-US-IRM_SSS_X64FREE_EN-US_DV5.ISO"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:3004f5265f1ef4350062ac1542e7f754be6aa359472a365e0f5cf558fc2e16a3d9675ba8fba5b04649bf6e68446d7515733cd5d46da7e1dae0bebe02576300a0"
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

  machine_type   = "pc"
  net_device     = "e1000"
  disk_interface = "ide"

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-global", "e1000.rombar=0"],
    ["-serial", "stdio"],
  ]

  cd_files = [
    "${path.root}/autounattend/Autounattend.xml",
    "${path.root}/autounattend/setup-ssh.cmd",
    "${path.cwd}/local/misc/OpenSSH-Win64.msi",
  ]
  cd_label = "cidata"

  boot_command = ["<return>", "<wait3>", "<return>", "<wait3>", "<return>"]
  boot_wait    = "2s"

  communicator = "ssh"
  ssh_username = "Administrator"
  ssh_password = "rotartsinimda"
  ssh_timeout  = "1h"

  shutdown_command = "shutdown /s /t 60 /f /d p:4:1 /c \"Packer Shutdown\""

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]
}
