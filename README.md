# Hardware-Accelerated_Local_Encryption
Wifi Access Point on Raspberry Pi Pico 2W to encrypt a 10 digit phone number with AES-128 on the DE10-lite board via SPI connection. 

# To run this project
**For the DE10-Lite**

Proj folder contents are to be compiled in Quartus Prime Lite. 
Open the project with Proj.qpf
Make sure that under files Proj.sv and aes_128.sv are included in the Project.
Proj needs to be set to Top-level entity.

Consider the [DE10-lite manual](https://ftp.intel.com/Public/Pub/fpgaup/pub/Intel_Material/Boards/DE10-Lite/DE10_Lite_User_Manual.pdf) for the next steps.
After having compiled the design go through the following steps:
Menu -> Assignments, and then -> Import Assignments and browse to where you saved the .qsf file.
Then click Program Device under task, and make sure you have selected USB-blaster before you click start.

**For the Raspberry Pi Pico 2W (may also work with Pico W refer to the respective data sheets for pin assignements)**

Make sure the Pico is in BOOTSEL mode by pressing down the BOOTSEL button while inserting the USB to your computer. 
If you are not using an IDE: 
If Pico is in BOOTSEL mode, it should show up on your PC's Devices and Drives, drag and drop the file into the device. 

If you are using Thonny IDE (recommended it is free):
Open apSet.py and make sure your ports are configured for Raspberry Pi Pico and device is inserted in BOOTSEL mode. 
Run current script and you can view the IP and connected device in the Thonny terminal below.

# To connect to the Pico's AP
Find the SSID Pico2W and enter the password "password". 
Once connected, go into any browser and enter the IP in the URL, this will take you to the HTTP server hosted on the Pico.
Enjoy! 
