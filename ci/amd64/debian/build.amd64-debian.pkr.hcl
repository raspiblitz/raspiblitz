variable "iso_name" { default = "debian-12.8.0-amd64-netinst.iso" }
variable "iso_checksum" { default = "04396d12b0f377958a070c38a923c227832fa3b3e18ddc013936ecf492e9fbb3" }

variable "pack" { default = "lean" }
variable "github_user" { default = "raspiblitz" }
variable "branch" { default = "dev" }
variable "desktop" { default = "none" }

variable "boot" { default = "uefi" }
variable "preseed_file" { default = "preseed.cfg" }
variable "hostname" { default = "raspiblitz-amd64" }

variable "disk_size" { default = "27000" }
variable "memory" { default = "4096" }
variable "cpus" { default = "4" }

locals {
  name_template = "${var.hostname}-debian-${var.pack}"
  bios_file     = var.boot == "uefi" ? "OVMF.fd" : "bios-256k.bin"
  boot_command = var.boot == "uefi" ? [
    "<wait><wait><wait>c<wait><wait><wait>",
    "linux /install.amd/vmlinuz ",
    "auto=true ",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.preseed_file} ",
    "hostname=${var.hostname} ",
    "domain=${var.hostname}.local ",
    "interface=auto ",
    "vga=788 noprompt quiet --<enter>",
    "initrd /install.amd/initrd.gz<enter>",
    "boot<enter>"
    ] : [
    "<esc><wait>install <wait>",
    "<wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait><wait> preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.preseed_file} <wait>",
    "debian-installer=en_US.UTF-8 <wait>",
    "auto <wait>",
    "locale=en_US.UTF-8 <wait>",
    "kbd-chooser/method=us <wait>",
    "keyboard-configuration/xkb-keymap=us <wait>",
    "netcfg/get_hostname=${var.hostname} <wait>",
    "netcfg/get_domain=${var.hostname}.local <wait>",
    "fb=false <wait>",
    "debconf/frontend=noninteractive <wait>",
    "console-setup/ask_detect=false <wait>",
    "console-keymaps-at/keymap=us <wait>",
    "grub-installer/bootdev=default <wait>",
    "<enter><wait>"
  ]
}

source "qemu" "debian" {
  boot_command     = local.boot_command
  boot_wait        = "5s"
  cpus             = var.cpus
  disk_size        = var.disk_size
  http_directory   = "./http"
  iso_checksum     = var.iso_checksum
  iso_url          = "https://cdimage.debian.org/cdimage/release/current/amd64/iso-cd/${var.iso_name}"
  memory           = var.memory
  output_directory = "../builds/${local.name_template}-qemu"
  shutdown_command = "echo 'raspiblitz' | sudo /sbin/shutdown -hP now"
  ssh_password     = "raspiblitz"
  ssh_port         = 22
  ssh_timeout      = "10000s"
  ssh_username     = "pi"
  format           = "qcow2"
  vm_name          = "${local.name_template}.qcow2"
  headless         = false
  vnc_bind_address = "127.0.0.1"
  vnc_port_max     = 5900
  vnc_port_min     = 5900
  qemuargs = [
    ["-m", var.memory],
    ["-bios", local.bios_file],
    ["-display", "none"]
  ]
}

build {
  description = "Can't use variables here yet!"
  sources     = ["source.qemu.debian"]

  provisioner "shell" {
    environment_vars = [
      "HOME_DIR=/home/pi",
      "github_user=${var.github_user}",
      "branch=${var.branch}",
      "pack=${var.pack}",
      "desktop=${var.desktop}"
    ]

    execute_command   = "echo 'raspiblitz' | {{.Vars}} sudo -S -E sh -eux '{{.Path}}'"
    expect_disconnect = true
    scripts = [
      "./../_common/env.sh",
      "./scripts/update.sh",
      "./../_common/sshd.sh",
      "./scripts/networking.sh",
      "./scripts/sudoers.sh",
      "./scripts/systemd.sh",
      "./scripts/build.raspiblitz.sh",
      "./scripts/cleanup.sh"
    ]
  }
}

packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.0, < 2.0.0"
    }
  }
}
