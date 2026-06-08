# macOS Sonoma (14)
variable "image" {
  type    = string
  default = "ghcr.io/cirruslabs/macos-sonoma-vanilla:14.8.7"
}

source "null" "macos-14" {
  communicator = "none"
}

build {
  sources = ["source.null.macos-14"]

  provisioner "shell-local" {
    inline = [
      "tart pull ${var.image}",
      "tart delete macos-14 >/dev/null 2>&1 || true",
      "tart clone ${var.image} macos-14",
      "src=\"$HOME/.tart/vms/macos-14/disk.img\"",
      "dst=\"${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk\"",
      "mkdir -p \"$(dirname \"$dst\")\"",
      "qemu-img convert -c -p -O qcow2 \"$src\" \"$dst\"",
      "tart delete macos-14",
    ]
  }

  post-processor "artifice" {
    files = ["${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}/disk"]
  }
}
