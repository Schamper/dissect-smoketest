# macOS Ventura (13)
variable "image" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-ventura-vanilla:13.6"
}

source "null" "macos-13" {
  communicator = "none"
}

build {
  sources = ["source.null.macos-13"]

  provisioner "shell-local" {
    inline = [
      "tart pull ${var.image}",
      "tart delete macos-13 >/dev/null 2>&1 || true",
      "tart clone ${var.image} macos-13",
      "src=\"$HOME/.tart/vms/macos-13/disk.img\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "qemu-img convert -c -p -O qcow2 \"$src\" \"$dst\"",
      "tart delete macos-13",
    ]
  }

  post-processor "artifice" {
    files = ["${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk"]
  }
}
