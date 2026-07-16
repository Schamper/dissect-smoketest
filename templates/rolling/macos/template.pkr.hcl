# macOS - rolling
packer {
  required_plugins {
    tart = {
      source  = "github.com/cirruslabs/tart"
      version = "~> 1.20"
    }
  }
}

variable "headless" {
  type    = bool
  default = true
}

source "tart-cli" "build" {
  vm_name            = "macos"
  from_ipsw          = "latest"
  cpu_count          = 4
  memory_gb          = 8
  disk_size_gb       = 60
  disk_format        = "asif"
  recovery_partition = "keep"
  headless           = var.headless

  ssh_username = "admin"
  ssh_password = "admin"
  ssh_timeout  = "1h"
}

build {
  sources = ["source.tart-cli.build"]

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/dissect-smoketest",
      "printf 'template=macos\\nlifecycle=rolling\\n' | sudo tee /etc/dissect-smoketest/provisioned >/dev/null",
      "sudo shutdown -h +1",
    ]
  }

  # Relocate tart's ASIF disk to the path the rest of the pipeline expects.
  # Dissect reads ASIF natively, so no conversion is needed.
  post-processor "shell-local" {
    inline = [
      "set -euo pipefail",
      "src=\"$HOME/.tart/vms/macos/disk.asif\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk.asif\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "cp \"$src\" \"$dst\"",
    ]
  }
}
