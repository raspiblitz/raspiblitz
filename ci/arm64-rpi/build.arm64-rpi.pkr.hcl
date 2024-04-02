variable "pack" { default = "lean" }
variable "github_user" { default = "raspiblitz" }
variable "branch" { default = "dev" }
variable "image_link" { default = "https://downloads.raspberrypi.org/raspios_arm64/images/raspios_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64.img.xz" }
variable "image_checksum" { default = "7e53a46aab92051d523d7283c080532bebb52ce86758629bf1951be9b4b0560f" }
variable "image_size" { default = "20G" }

source "arm" "raspiblitz-arm64-rpi" {
  file_checksum_type    = "sha256"
  file_checksum         = var.image_checksum
  file_target_extension = "xz"
  file_unarchive_cmd    = ["xz", "--decompress", "$ARCHIVE_PATH"]
  file_urls             = [var.image_link]
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
  image_size                   = var.image_size
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
      "apt-get update",
      "apt-get install -y sudo wget",
      "apt-get -y autoremove",
      "apt-get -y clean",
      "touch /boot/ssh",
      "echo 'pi:$6$TE7HmruYY9EaNiKP$Vz0inJ6gaoJgJvQrC5z/HMDRMTN2jKhiEnG83tc1Jsw7lli5MYdeA83g3NOVCsBaTVW4mUBiT/1ZRWYdofVQX0' > /boot/userconf"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "github_user=${var.github_user}",
      "branch=${var.branch}",
      "pack=${var.pack}"
    ]
    script = "./build.raspiblitz.sh"
  }

  provisioner "shell" {
    inline = [
      "echo '# delete the SSH keys (will be recreated on the first boot)'",
      "rm -f /etc/ssh/ssh_host_*",
      "echo 'OK'",
    ]
  }

  provisioner "shell" {
    inline = [
      "if [ \"${var.pack}\" = \"base\" ]; then lsblk; ls -la /boot/; echo 'Adding stop file to /boot/firmware/'; touch /boot/firmware/stop; fi"
    ]
  }
}
