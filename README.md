# usbctl
Lua-lgi/Gtk based GUI for controlling a USB hub with [uhubctl](https://github.com/mvp/uhubctl)

## Screenshot
<img width="190" height="298" alt="usbctl" src="https://github.com/user-attachments/assets/b36764fa-9b40-4b3d-ab9c-bb9c1b741d9d" />

## Requirements
* lua-lgi
* luasocket
* Gtk/Gdk
* [uhubctl](https://github.com/mvp/uhubctl)

## Important
You have to manually set the **ports** assignment in the source to your USB port paths!  
You also have to make sure the user permissions for uhubctl are correct. usbctl monitors dmesg to detect USB (un)plug events.

Unfortunately there is no further documentation at the moment, so you may have to take a look at the source 😅  
If you want to contribute documentation please do so 🙂
