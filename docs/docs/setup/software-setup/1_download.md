---
sidebar_position: 1
---

# Download / Flash
## Downloading the Software

In this section you find the latest ready-to-use RaspiBlitz SDcard images. Basically you just download, write/flash the image file to an sd card and start your RaspberryPi with it - its the same for first install or updating to a newer version. You can choose from two ready-made sd card images below:

### FATPACK SD Card Image (Beginners - WebUI)

This is the sd card image you should choose if your at the beginning of your RaspiBlitz journey or you are a casual node runner wanna download the next update/upgrade - with WebUI & fast installing bonus apps.

:::warning
THIS IS STILL A RELEASE CANDIDATE VERSION JUST USE FOR TESTING, HIGHER RISK OF LOSING FUNDS!
:::

- FATPACK SD CARD IMAGE ⮕ [raspiblitz-fat-v1.10.0rc6-2023-09-22.img.gz](https://raspiblitz.fulmo.org/images/raspiblitz-fat-v1.10.0rc6-2023-09-22.img.gz)**
- SHA-256: 50b48e078d162dfafc2b80025cf493141b0d8ab5774519bff4c3239d5d246f8f
- GPG 64-bit (main): 1C73 060C 7C17 6461 & (sub): AA9D D1B5 CC56 47DA
- Signature-File: [raspiblitz-fat-v1.9.0-2023-05-22.img.gz.sig](https://raspiblitz.fulmo.org/images/raspiblitz-fat-v1.9.0-2023-05-22.img.gz.sig)
- Torrent: [raspiblitz-fat-v1.9.0-2022-12-21.img.gz.torrent](https://github.com/rootzoll/raspiblitz/raw/dev/home.admin/assets/raspiblitz-fat-v1.9.0-2023-05-22.img.gz.torrent)
- [How to verify the SD card image after download?](../../faq/faq.md#how-to-verify-the-sd-card-image-after-download)

### MINIMAL SD Card Image (Experienced Users - SSH)

This is the sd card image for RaspiBlitz users that are already more experienced and want to use just a limited set of features of the RaspiBlitz. This image has just the bare minimum of features pre-installed - LCD & HDMI output is off by default. Setup, Update or Recovery needs to be done thru SSH login - API & WebUI are later available but are not preinstalled/activated by default. The RaspiBlitz will download & compile just the tools that are in your ´raspiblitz.conf´ - this will take longer but as a trade-off this RaspiBlitz then just runs with a reduced set of dependencies and so a minimalized attack vector and better performance. Its for the serious & experienced node runners.

:::warning
THIS IS STILL A RELEASE CANDIDATE VERSION JUST USE FOR TESTING, HIGHER RISK OF LOSING FUNDS!
:::


- **MINIMAL SD CARD IMAGE ⮕ [raspiblitz-min-v1.10.0rc6-2023-09-22.img.gz](https://raspiblitz.fulmo.org/images/raspiblitz-min-v1.10.0rc6-2023-09-22.img.gz)**
- SHA-256: 77674947b6682cfcc507179038ad532d4b7e60eb5274edca1a62ee78882108ad
- GPG 64-bit (main): 1C73 060C 7C17 6461 & (sub): AA9D D1B5 CC56 47DA
- Signature-File: [raspiblitz-min-v1.9.0-2023-05-22.img.gz.sig](https://raspiblitz.fulmo.org/images/raspiblitz-min-v1.9.0-2023-05-22.img.gz.sig)
- Torrent: [raspiblitz-min-v1.9.0-2022-12-21.img.gz.torrent](https://github.com/rootzoll/raspiblitz/raw/dev/home.admin/assets/raspiblitz-min-v1.9.0-2023-05-22.img.gz.torrent)
- [How to verify the SD card image after download?](../../faq/faq.md#how-to-verify-the-sd-card-image-after-download)

Further Info:

```
TODO: fixme
- What's new in Version 1.9.0 of RaspiBlitz? https://github.com/fusion44/raspiblitz/blob/95c495ea0195765d3391eb9603e6cdeb24075c2c/CHANGES.md
- How to update my RaspiBlitz? README.md#updating-raspiblitz-to-new-version
- How to migrate to RaspiBlitz from Umbrel/myNode/Citadel #make-a-raspiblitz-out-of-your-umbrel-citadel-or-mynode
```
## Write the SD-Card image to your SD Card

You need to write the downloaded SD card image (the img.gz-file) to your SD card (32GB minimum) - you can use the very easy tool [Balena Etcher](https://www.balena.io/etcher/) for this: .
It's available for Win, Mac & Linux.
