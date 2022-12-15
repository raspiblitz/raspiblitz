variable "pack" {}
variable "github_user" {}
variable "branch" {}

source "arm" "raspiblitz-arm64-rpi" {
  file_checksum_type    = "sha256"
  file_checksum         = "c42856ffca096480180b5aff66e1dad2f727fdc33359b24e0d2d49cc7676b576"
  file_target_extension = "xz"
  file_unarchive_cmd    = ["xz", "--decompress", "$ARCHIVE_PATH"]
  file_urls             = ["https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2022-09-26/2022-09-22-raspios-bullseye-arm64.img.xz"]
  image_build_method    = "resize"
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
  image_path                   = "raspiblitz-arm64-rpi-${var.pack}.img"
  image_size                   = "32G"
  image_type                   = "dos"
  qemu_binary_destination_path = "/usr/bin/qemu-arm-static"
  qemu_binary_source_path      = "/usr/bin/qemu-arm-static"
}

build {
  sources = ["source.arm.raspiblitz-arm64-rpi"]

  provisioner "shell" {
    inline = [
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf",
      "echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections",
      "apt-get install -y sudo wget",
      "apt-get -y autoremove",
      "apt-get -y clean",
    ]
  }

  provisioner "shell" {
    environment_vars =  [
      "github_user=${var.github_user}",
      "branch=${var.branch}",
      "pack=${var.pack}"
    ]
    script = "./raspiblitz.sh"
  }

  provisioner "shell" {
    inline = [
      "echo '# delete the SSH keys (will be recreated on the first boot)'",
      "rm -f /etc/ssh/ssh_host_*",
      "echo 'OK'",
    ]
  }
}
