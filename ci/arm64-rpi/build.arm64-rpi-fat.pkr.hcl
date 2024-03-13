variable "github_user" { default = "raspiblitz" }
variable "branch" { default = "dev" }
variable "artifact" { default = "file:/build/raspiblitz-arm64-rpi-lean.img" }
variable "image_checksum" { default = "not_available" }

source "arm" "raspiblitz-arm64-rpi-fat" {
  file_urls = [var.artifact]
  file_checksum_type = "sha256"
  file_checksum         = var.image_checksum
  file_target_extension = "img"

  image_build_method    = "reuse"
  image_chroot_env      = ["PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"]
  image_partitions {
    filesystem   = "vfat"
    mountpoint   = "/boot"
    name         = "boot"
    size         = "256M"
    start_sector = "8192"
    type         = "c"
  }
  image_partitions {
    filesystem   = "ext4"
    mountpoint   = "/"
    name         = "root"
    size         = "0"
    start_sector = "532480"
    type         = "83"
  }
  image_path                   = "raspiblitz-arm64-rpi-fat.img"
  image_size                   = "20G"
  image_type                   = "dos"
  qemu_binary_destination_path = "/usr/bin/qemu-arm-static"
  qemu_binary_source_path      = "/usr/bin/qemu-arm-static"
}

build {
  sources = ["source.arm.raspiblitz-arm64-rpi-fat"]

  provisioner "shell" {
    environment_vars = [
      "github_user=${var.github_user}",
      "branch=${var.branch}",
    ]
    script = "./build.raspiblitz-fat.sh"
  }
}
