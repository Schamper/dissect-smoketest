# Windows LDM corpus
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

  # Turn the (BIOS/MBR) boot disk into a dynamic disk so it carries an LDM
  # database. This has to happen in three steps:
  #
  #   1. convert dynamic  - because disk 0 holds the in-use system and boot
  #      volumes, diskpart only *starts* the conversion; it cannot finish (nor
  #      create new volumes on the disk) until the machine reboots.
  #   2. reboot           - completes the conversion of the system/boot volumes.
  #      The SSH communicator reconnects once OpenSSH is back up.
  #   3. create volume    - only now can a simple LDM volume be carved out of the
  #      free space the installer left unallocated.
  provisioner "powershell" {
    inline = [
      "$s = @('select disk 0','convert dynamic noerr')",
      "$s | Out-File -Encoding ascii -FilePath C:\\ldm-convert.txt",
      "diskpart /s C:\\ldm-convert.txt",
      "Remove-Item -Force C:\\ldm-convert.txt",
    ]
  }

  provisioner "powershell" {
    inline = ["shutdown /r /t 5 /f /c \"ldm dynamic conversion reboot\""]
  }

  provisioner "powershell" {
    pause_before = "90s"
    inline = [
      "$s = @('select disk 0','create volume simple disk=0','format fs=ntfs quick label=DATA','assign letter=Z')",
      "$s | Out-File -Encoding ascii -FilePath C:\\ldm-volume.txt",
      "diskpart /s C:\\ldm-volume.txt",
      "Set-Content -Path Z:\\secret.txt -Value 'kusjes van SRT <3'",
      "Remove-Item -Force C:\\ldm-volume.txt",
    ]
  }
}
