# ext4 native encryption (fscrypt) on Debian — dedicated /home partition with
# the encrypt feature, passphrase: password
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
  default = "https://cdimage.debian.org/cdimage/archive/13.5.0/amd64/iso-cd/debian-13.5.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "file:https://cdimage.debian.org/cdimage/archive/13.5.0/amd64/iso-cd/SHA256SUMS"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "8G"
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

  http_directory = "${path.root}/preseed"

  boot_command = [
    "<esc><wait>",
    "install auto=true priority=critical url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg",
    "<enter>",
  ]
  boot_key_interval = "10ms"
  boot_wait         = "5s"

  communicator = "ssh"
  ssh_username = "user"
  ssh_password = "password"
  ssh_timeout  = "30m"

  shutdown_command = "sudo poweroff"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    inline = [
      # The preseed late_command already enabled the encrypt feature on /home and
      # installed fscrypt. Finish the setup: initialise fscrypt, create an
      # encrypted directory, write a test file, then lock it.
      "sudo fscrypt setup --force",
      "sudo fscrypt setup /home",
      "sudo mkdir ~/.encrypted",
      "printf 'password\\npassword\\n' | sudo fscrypt encrypt ~/.encrypted --source=custom_passphrase --name=dissect --quiet",
      "echo 'kusjes van SRT <3' | sudo tee ~/.encrypted/secret.txt > /dev/null",
      "sudo fscrypt lock ~/.encrypted --all-users || true",
    ]
  }
}
