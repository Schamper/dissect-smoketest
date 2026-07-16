# NixOS 26.05
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# Pinned to a specific NixOS 26.05 channel bump. To bump:
# 1. Pick a build from https://releases.nixos.org/?prefix=nixos/26.05/
# 2. Update the URLs for the ISO and the checksum
variable "iso_url" {
  type    = string
  default = "https://releases.nixos.org/nixos/26.05/nixos-26.05.3869.95ca1e203c07/nixos-minimal-26.05.3869.95ca1e203c07-x86_64-linux.iso"
}

variable "iso_checksum" {
  type    = string
  default = "ce2784752f03d52e4b6511a78375655377ef30e41ac8c78ecd0baebfd6a5506c"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "10G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 2048
  headless  = var.headless

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  # The installer auto-logs in as the passwordless-sudo "nixos" user; drive a
  # scripted install off Packer's HTTP server, then reboot into the new system.
  http_directory = "${path.root}/nixos"

  boot_command = [
    "sudo -i<enter><wait>",
    # Create partitions
    "fdisk /dev/vda<enter><wait>",
    "o<enter>n<enter>p<enter>1<enter>2048<enter>+500M<enter>n<enter>p<enter>2<enter><enter><enter>w<enter><wait>",
    "mkfs.fat -F 32 /dev/vda1<enter><wait>",
    "fatlabel /dev/vda1 NIXBOOT<enter><wait>",
    "mkfs.ext4 /dev/vda2 -L NIXROOT<enter><wait>",
    "mount /dev/disk/by-label/NIXROOT /mnt<enter><wait>",
    "mkdir -p /mnt/boot<enter><wait>",
    "mount /dev/disk/by-label/NIXBOOT /mnt/boot<enter><wait>",
    # Generate config
    "sudo nixos-generate-config --root /mnt<enter><wait>",
    # Overwrite config with ours
    "curl -sSf http://{{ .HTTPIP }}:{{ .HTTPPort }}/configuration.nix -o /mnt/etc/nixos/configuration.nix<enter><wait>",
    "curl -sSf http://{{ .HTTPIP }}:{{ .HTTPPort }}/hardware-configuration.nix -o /mnt/etc/nixos/hardware-configuration.nix<enter><wait>",
    "cd /mnt && sudo nixos-install<enter><wait10m>",
    "password<enter>password<enter><wait>",
    "reboot -h now<enter>",
  ]
  boot_key_interval = "20ms"
  boot_wait         = "1m"

  communicator = "ssh"
  ssh_username = "user"
  ssh_password = "password"
  ssh_timeout  = "45m"

  shutdown_command = "echo 'password' | sudo -S poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = ["test -f /etc/dissect-smoketest/provisioned"]
  }
}
