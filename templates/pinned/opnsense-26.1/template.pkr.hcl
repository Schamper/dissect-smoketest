# OPNsense
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
  default = "https://pkg.opnsense.org/releases/26.1.6/OPNsense-26.1.6-dvd-amd64.iso.bz2"
}

variable "iso_checksum" {
  type    = string
  default = "6ba3633d9c0f96d82c792015a45f4b8aac45ea8fa2bdba3c5e534d0c90a4f08c"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "16G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 4096
  headless  = var.headless

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-serial", "stdio"],
  ]

  boot_command = [
    "installer<enter><wait>opnsense<enter><wait5>",
    "<enter><wait5>",                                            # Default keymap
    "<enter><wait15>",                                           # Install
    "<enter><wait5>",                                            # Select RAID (stripe)
    "<spacebar><wait><enter><wait5>",                            # Select disk
    "<left><wait><enter><wait10m>",                              # Confirm
    "<enter><wait>password<enter><wait>password<enter><wait1m>", # Change root password
    "<down><wait><enter><wait><enter><wait2m>",                  # Finish and reboot
    "root<enter><wait>password<enter><wait>",                    # Login
    "2<wait><enter><wait>",                                      # Enter interface settings
    "y<enter><wait>",                                            # Configure DHCP (IPv4)
    "<enter><wait>",                                             # Ignore DHCP (IPv6)
    "<enter><wait>",                                             # Leave IPv6 empty
    "<enter><wait>",                                             # Don't change from HTTPS to HTTP
    "<enter><wait>",                                             # Don't regenerate new certificates
    "<enter><wait>",                                             # Don't restore web GUI defaults

    "8<enter><wait5>", # Drop to a shell (console menu option 8)
    # Persistently enable SSH (root + password auth) in config.xml via OPNsense's
    # own config API, then let configd render sshd_config, generate host keys and
    # start the service.
    "php -r 'require_once(\"config.inc\"); require_once(\"system.inc\"); require_once(\"util.inc\"); $config[\"system\"][\"ssh\"][\"enabled\"]=\"enabled\"; $config[\"system\"][\"ssh\"][\"permitrootlogin\"]=\"1\"; $config[\"system\"][\"ssh\"][\"passwordauth\"]=\"1\"; write_config(\"enable ssh for packer\");'<enter><wait5>",
    "configctl openssh restart<enter><wait>",
    "exit<enter><wait>", # Back to the console menu
  ]
  boot_key_interval = "20ms"
  boot_wait         = "2m"

  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "password"
  ssh_timeout  = "1h"

  shutdown_command = "shutdown -p now"

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
    inline = [
      "mkdir -p /etc/dissect-smoketest",
      "printf 'template=opnsense-26.1\\nlifecycle=pinned\\n' > /etc/dissect-smoketest/provisioned",
    ]
  }
}
