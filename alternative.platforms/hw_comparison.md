## SBC benchmarks:

https://github.com/ThomasKaiser/sbc-bench/blob/master/Results.md

https://dietpi.com/survey/#benchmark

### Raspberry Pi 5 (Recommended)

* SoC: Broadcom BCM2712 quad-core Cortex-A76 (ARMv8-A) 64-bit @ 2.4GHz
* GPU: VideoCore VII
* Networking: 2.4 GHz and 5 GHz 802.11b/g/n/ac wireless LAN, Gigabit Ethernet (PoE+ supported via separate HAT)
* RAM: 4GB or 8GB LPDDR4X SDRAM
* Bluetooth: Bluetooth 5.0, Bluetooth Low Energy (BLE)
* GPIO: 40-pin GPIO header (new pinout — see [Raspberry Pi documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi-5.html))
* Storage: microSD for initial boot; **NVMe SSD via PCIe HAT** (recommended for production — see [NVMe storage section](#nvme-storage-recommendations) below)
* Ports: 2 × micro-HDMI 2.1, 2 × USB 3.0, 2 × USB 2.0, Gigabit Ethernet (PoE+), 4-pin PCIe 2.0 x1 FPC interface, CSI/DSI via FPC ribbon cables
* Dimensions: 85 mm × 56 mm × 12 mm, 46 g
* Power: USB-C 5V/5A (27W PD)

The Pi 5 is the recommended platform for RaspiBlitz as of v1.11+. The PCIe FPC connector enables direct NVMe SSD attachment via a compatible HAT, providing significantly better I/O performance than USB SSDs or microSD cards.

### Raspberry Pi 4

* SoC: Broadcom BCM2711B0 quad-core A72 (ARMv8-A) 64-bit @ 1.5GHz
* GPU: Broadcom VideoCore VI
* Networking: 2.4 GHz and 5 GHz 802.11b/g/n/ac wireless LAN
* RAM: 1GB, 2GB, 4GB, or 8GB LPDDR4 SDRAM
* Bluetooth: Bluetooth 5.0, Bluetooth Low Energy (BLE)
* GPIO: 40-pin GPIO header, populated
* Storage: microSD
* Ports: 2 × micro-HDMI 2.0, 3.5 mm analogue audio-video jack, 2 × USB 2.0, 2 × USB 3.0, Gigabit Ethernet, Camera Serial Interface (CSI), Display Serial Interface (DSI)
* Dimensions: 88 mm × 58 mm × 19.5 mm, 46 g

###  Raspberry Pi 3 Model B+

* Broadcom BCM2837B0, Cortex-A53 (ARMv8) 64-bit SoC @ 1.4GHz
* 1GB LPDDR2 SDRAM
* 2.4GHz and 5GHz IEEE 802.11.b/g/n/ac wireless LAN, Bluetooth 4.2, BLE
* Gigabit Ethernet over USB 2.0 (maximum throughput 300 Mbps)
* Extended 40-pin GPIO header
* Full-size HDMI
* 4 USB 2.0 ports
* CSI camera port for connecting a Raspberry Pi camera
* DSI display port for connecting a Raspberry Pi touchscreen display
* 4-pole stereo output and composite video port
* Micro SD port for loading your operating system and storing data
* 5V/2.5A DC power input
* Power-over-Ethernet (PoE) support (requires separate PoE HAT)

> **Note:** The Raspberry Pi 3B+ is no longer recommended for new RaspiBlitz installations due to limited RAM and I/O performance. Consider upgrading to Pi 4 or Pi 5.

### NVMe Storage Recommendations

For Raspberry Pi 5 with a PCIe HAT (e.g., Pimoroni NVMe Base, Radxa Penta SATA/NVMe HAT, or Pineberry Pi NVMe HAT):

* **Minimum:** 500 GB NVMe M.2 SSD (2230 or 2280 form factor, depending on HAT)
* **Recommended:** 1 TB+ NVMe SSD for comfortable Bitcoin full node + Lightning
* **Interface:** PCIe 2.0 x1 via the Pi 5 FPC connector (max ~500 MB/s)
* **Form factor:** M.2 2280 is most common; check your HAT's supported sizes
* **TLC over QLC:** Prefer TLC NAND for better sustained write endurance under blockchain workloads
* **Power draw:** M.2 SSDs typically draw 2-5W — ensure your power supply can handle Pi 5 + HAT + SSD + USB peripherals (5V/5A minimum, 5V/5A PD recommended)

With RaspiBlitz v1.12+, the system can boot and run entirely from NVMe, eliminating the need for a microSD card as the OS drive.

For a full compatibility list, see the [RPi PCIe NVMe adapter compatibility database](https://pipci.jeffgeerling.com/#m2-and-nvme-adapters) and [Pimoroni NVMe Base compatibility list](https://shop.pimoroni.com/products/nvme-base?variant=41219587178579).

> **Note:** Avoid QLC NAND SSDs (e.g., Crucial P3 Plus) for node operation — they may exhibit high IO wait times under sustained write loads. See [issue #4745](https://github.com/raspiblitz/raspiblitz/issues/4745) for community discussion.

### Odroid HC1

* Samsung Exynos5422 Octa core CPU 4x Cortex-A15 2Ghz and 4x Cortex-A7 1.5GHz
* 2 Gbyte LPDDR3 RAM
* SATA-3 port for 2.5inch HDD/SSD storage up to 15mm thickness
* Gigabit Ethernet port
* USB 2.0 Host
* UHS-1 capable micro-SD card slot for boot media
* Size : 147 x 85 x 29 mm approx.(including Aluminium cooling frame)
* Linux server OS images based on modern Kernel 4.14 LTS

![HC1](/alternative.platforms/pictures/HC1.jpg)

### Odroid XU4

* Samsung Exynos5422 Octa core CPU 4x Cortex-A15 2Ghz and 4x Cortex-A7 1.5GHz
* 2 Gbyte LPDDR3 RAM 
* Graphics: Samsung S2MPS11
* Storage: eMMC5.0 HS400 Flash Storage or SD Card
* I/O Connectors: HDMI-A x 1, USB 3.0 Host x 2, USB 2.0 Host x 1, PWM for * Cooler Fan, UART for serial console 30Pin : GPIO/IRQ/SPI/ADC, 12Pin : GPIO/I2S/I2C
* Network Ethernet RJ-45
* Input Power 5V

![XU4](/alternative.platforms/pictures/XU4.jpg)