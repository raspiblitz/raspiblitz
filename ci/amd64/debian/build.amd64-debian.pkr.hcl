packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.0.0, < 2.0.0"
    }
  }
}

variable "pack" { default = "lean" }
variable "github_user" { default = "raspiblitz" }
variable "branch" { default = "dev" }
variable "desktop" { default = "none" }

variable "qemu_bios" { default = "OVMF.fd" }
variable "preseed_file" { default = "preseed.cfg" }

variable "iso_name" { default = "debian-12.1.0-amd64-netinst.iso" }
variable "iso_checksum" { default = "9f181ae12b25840a508786b1756c6352a0e58484998669288c4eec2ab16b8559" }

variable "disk_size" { default = "30000" }
variable "memory" { default = "4096" }
variable "cpus" { default = "4" }
variable "headless" { default = "false" }
variable "build_directory" { default = "../builds" }

variable "hostname" { default = "raspiblitz-amd64" }
variable "name_template" { default = "raspiblitz-amd64-debian" }

variable "mirror" { default = "http://cdimage.debian.org/cdimage/release" }
variable "mirror_directory" { default = "current/amd64/iso-cd" }

source "qemu" "debian" {
  boot_command = [
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
  ]
  boot_wait        = "5s"
  cpus             = var.cpus
  disk_size        = var.disk_size
  headless         = var.headless
  http_directory   = "./http"
  iso_checksum     = var.iso_checksum
  iso_url          = "${var.mirror}/${var.mirror_directory}/${var.iso_name}"
  memory           = var.memory
  output_directory = "${var.build_directory}/${var.name_template}-${var.pack}-qemu"
  shutdown_command = "echo 'raspiblitz' | sudo /sbin/shutdown -hP now"
  ssh_password     = "raspiblitz"
  ssh_port         = 22
  ssh_timeout      = "10000s"
  ssh_username     = "pi"
  format           = "qcow2"
  vm_name          = "${var.name_template}-${var.pack}.qcow2"
  vnc_bind_address = "127.0.0.1"
  vnc_port_max     = 5900
  vnc_port_min     = 5900
  qemuargs = [
    ["-m", "${var.memory}"],
    ["-bios", "${var.qemu_bios}"],
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
