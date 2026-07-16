# macOS Monterey (12)
variable "image" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-monterey-vanilla:12.7.6"
}

source "null" "macos-12" {
  communicator = "none"
}

build {
  sources = ["source.null.macos-12"]

  provisioner "shell-local" {
    inline = [
      "tart pull ${var.image}",
      "tart delete macos-12 >/dev/null 2>&1 || true",
      "tart clone ${var.image} macos-12",
      "src=\"$HOME/.tart/vms/macos-12/disk.img\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "qemu-img convert -c -p -O qcow2 \"$src\" \"$dst\"",
      "tart delete macos-12",
    ]
  }

  post-processor "artifice" {
    files = ["${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk"]
  }
}
