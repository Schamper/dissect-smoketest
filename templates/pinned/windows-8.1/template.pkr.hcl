# Windows 8.1 Enterprise (x64)
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
  default = "https://download.microsoft.com/download/B/9/9/B999286E-0A47-406D-8B3D-5B5AD7373A4A/9600.17050.WINBLUE_REFRESH.140317-1640_X64FRE_ENTERPRISE_EVAL_EN-US-IR3_CENA_X64FREE_EN-US_DV9.ISO"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:b1ea789d0e66e81e2c85b2e790009bbdec389fe17fc1812908e14db77e312a0f3fe61f97020415512b6b07ae6ee6cc108b5c880d3a56e8f2eebb2b04909cfc02"
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
