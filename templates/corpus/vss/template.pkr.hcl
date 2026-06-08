# Windows VSS corpus
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
  default = "http://care.dlservice.microsoft.com/dl/download/evalx/win7/x64/EN/7600.16385.090713-1255_x64fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENXEVAL_EN_DVD.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha512:bb6d6ae1b5d2506e65a33aed26663541c2598cfc6a0d2da7067ad6720323aeb76adde8e59cc33bf06ac191953240a5ba9d688f5bcb16988a764c341400646d02"
}

variable "headless" {
  type    = bool
  default = true
}

source "qemu" "build" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  disk_size          = "32G"
  disk_discard       = "unmap"
  disk_detect_zeroes = "on"
  disk_compression   = true
  format             = "qcow2"

  cpu_model = "host"
  cpus      = 2
  memory    = 2048
  headless  = var.headless

  machine_type   = "pc"
  net_device     = "e1000"
  disk_interface = "ide"

  qemuargs = [
    ["-machine", "accel=kvm:hvf:whpx:tcg"],
    ["-netdev", "user,id=net0,restrict=on,hostfwd=tcp::{{ .SSHHostPort }}-:22"],
    ["-device", "e1000,netdev=net0"],
    ["-global", "e1000.rombar=0"],
    ["-serial", "stdio"],
  ]

  cd_files = ["${path.root}/autounattend/Autounattend.xml", "${path.root}/autounattend/setup-ssh.cmd", "${path.cwd}/local/misc/OpenSSH-Win64.msi"]
  cd_label = "cidata"

  boot_command = ["<return>", "<wait3>", "<return>", "<wait3>", "<return>"]
  boot_wait    = "2s"

  communicator = "ssh"
  ssh_username = "Administrator"
  ssh_password = "rotartsinimda"
  ssh_timeout  = "1h"

  shutdown_command = "shutdown /s /t 60 /f /d p:4:1 /c \"Packer Shutdown\""

  output_directory = "${path.cwd}/local/build/${basename(dirname(path.root))}/${basename(path.root)}"
  vm_name          = "disk"
}

build {
  sources = ["source.qemu.build"]

  # Build a VSS corpus with three distinct shadow-copy states
  #
  # File state matrix:
  #   File                    | Snap 1 | Snap 2 | Live
  #   original.txt            |   Y    |   Y    |   Y
  #   deleted.txt             |   Y    |   N    |   N
  #   modified.txt            |   v1   |   v2   |   v2
  #   added-1.txt             |   X    |   Y    |   Y
  #   added-2.txt             |   X    |   X    |   Y
  provisioner "powershell" {
    inline = [
      # Enable System Protection on C: so the ClientAccessible VSS context is
      # available.  The call is idempotent if already enabled.
      "Enable-ComputerRestore -Drive 'C:\\' -ErrorAction SilentlyContinue",
      "Set-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore' -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord",

      # Create the test directory and baseline files.
      "New-Item -ItemType Directory -Path C:\\vss -Force | Out-Null",
      "Set-Content 'C:\\vss\\original.txt' 'Kusjes van SRT <3'",
      "Set-Content 'C:\\vss\\deleted.txt'  'No more kusjes van SRT </3'",
      "Set-Content 'C:\\vss\\modified.txt' 'Many kusjes van SRT <3'",

      # Snapshot 1
      "$null = Invoke-WmiMethod -Namespace root/cimv2 -Class Win32_ShadowCopy -Name Create -ArgumentList 'C:\\','ClientAccessible'",

      # Mutate: delete, modify, add
      "Remove-Item -Force 'C:\\vss\\deleted.txt'",
      "Set-Content 'C:\\vss\\modified.txt' 'Many more kusjes van SRT <3'",
      "Set-Content 'C:\\vss\\added-1.txt'  'Where are we going with this? To MORE kusjes van SRT <3 <3'",

      # Snapshot 2
      "$null = Invoke-WmiMethod -Namespace root/cimv2 -Class Win32_ShadowCopy -Name Create -ArgumentList 'C:\\','ClientAccessible'",

      # Post-snap2 addition (live volume only)
      "Set-Content 'C:\\vss\\added-2.txt'  'Thanks for all the fish. Kusjes van SRT <3'",
    ]
  }
}
