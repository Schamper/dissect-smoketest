# OpenWrt x86-64 (squashfs + overlay)
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
  default = "https://downloads.openwrt.org/releases/25.12.4/targets/x86/64/openwrt-25.12.4-x86-64-generic-ext4-combined.img.gz"
}

variable "iso_checksum" {
  type    = string
  default = "9d080bcae28d7cdf86dabb4b29c10d36d89e0bd79e20a4799454380bc1619695"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_image         = true
  disk_size          = "512M"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 1
  memory    = 512
  headless  = var.headless

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  # OpenWrt auto-logs in as root on the serial console. Set a root password and
  # switch the LAN interface to DHCP so QEMU user-net hands the guest 10.0.2.15,
  # making dropbear reachable through Packer's SSH host-forward.
  boot_command = [
    "<enter><wait>",
    "passwd<enter><wait>password<enter><wait>password<enter><wait>",
    "uci set network.lan.proto='dhcp'<enter>",
    "uci -q delete network.lan.ipaddr<enter>",
    "uci -q delete network.lan.netmask<enter>",
    "uci commit network<enter>",
    "/etc/init.d/network restart<enter><wait5>",
  ]
  boot_key_interval = "20ms"
  boot_wait         = "30s"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "15m"

  shutdown_command = "poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = [
      "mkdir -p /etc/dissect-smoketest",
      "printf 'template=openwrt-25.12\\nlifecycle=pinned\\n' > /etc/dissect-smoketest/provisioned",
    ]
  }
}
