packer {
  required_plugins {
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1"
    }
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

variable "branch" {
  type    = string
  default = "dev"
}

variable "github_user" {
  type    = string
  default = "raspiblitz"
}

variable "iso_checksum" {
  type    = string
  default = "ade3a4acc465f59ca2496344aab72455945f3277a52afc5a2cae88cdc370fa12"
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.6.0-amd64-netinst.iso"
}

source "virtualbox-iso" "raspiblitz" {
  boot_command     = ["<esc><wait>auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<wait><enter>"]
  boot_wait        = "5s"
  disk_size        = "16384"
  guest_os_type    = "Debian_64"
  headless         = false
  http_directory   = "http"
  iso_checksum     = "sha256:${var.iso_checksum}"
  iso_url          = "${var.iso_url}"
  shutdown_command = "echo 'vagrant'|sudo -S shutdown -P now"
  ssh_password     = "vagrant"
  ssh_port         = 22
  ssh_timeout      = "30m"
  ssh_username     = "vagrant"
  vboxmanage       = [["modifyvm", "{{ .Name }}", "--memory", "1024"], ["modifyvm", "{{ .Name }}", "--cpus", "1"]]
  vm_name          = "raspiblitz-amd64"
}

build {
  sources = ["source.virtualbox-iso.raspiblitz"]

  provisioner "shell" {
    execute_command = "echo 'vagrant' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "scripts/init.sh"
  }

  provisioner "shell" {
    execute_command = "echo 'vagrant' | {{ .Vars }} sudo -S -E bash '{{ .Path }}' -i 0 -b ${var.branch} -u ${var.github_user} -d headless -w off"
    script          = "../../../build_sdcard.sh"
  }

  provisioner "shell" {
    execute_command = "echo 'vagrant' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script          = "scripts/cleanup.sh"
  }

  post-processor "vagrant" {
    compression_level = "8"
    output            = "output/raspiblitz.box"
  }
}
