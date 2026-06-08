# macOS Sequoia (15)
variable "image" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-sequoia-vanilla:15.7.7"
}

source "null" "macos-15" {
  communicator = "none"
}

build {
  sources = ["source.null.macos-15"]

  provisioner "shell-local" {
    inline = [
      "tart pull ${var.image}",
      "tart delete macos-15 >/dev/null 2>&1 || true",
      "tart clone ${var.image} macos-15",
      "src=\"$HOME/.tart/vms/macos-15/disk.img\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "qemu-img convert -c -p -O qcow2 \"$src\" \"$dst\"",
      "tart delete macos-15",
    ]
  }

  post-processor "artifice" {
    files = ["${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk"]
  }
}
