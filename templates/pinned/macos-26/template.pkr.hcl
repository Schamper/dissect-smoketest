# macOS Tahoe (26)
variable "image" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-tahoe-vanilla:26.5"
}

source "null" "macos-26" {
  communicator = "none"
}

build {
  sources = ["source.null.macos-26"]

  provisioner "shell-local" {
    inline = [
      "tart pull ${var.image}",
      "tart delete macos-26 >/dev/null 2>&1 || true",
      "tart clone ${var.image} macos-26",
      "src=\"$HOME/.tart/vms/macos-26/disk.img\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "qemu-img convert -c -p -O qcow2 \"$src\" \"$dst\"",
      "tart delete macos-26",
    ]
  }

  post-processor "artifice" {
    files = ["${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk"]
  }
}
