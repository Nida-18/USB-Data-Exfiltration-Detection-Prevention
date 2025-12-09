# USB Data Exfiltration Prevention & Transfer Monitor

A lightweight Bash script that prevents unauthorized USB drives from being accessed and blocks large data transfers (500 MB+) without an overwrite password.

## Features
- **UUID Whitelisting:** Trusted USB drives mount automatically without a prompt.
- **Password Protection:** Untrusted USB drives require a password before mounting.
- **Exfiltration Prevention:** Monitors data written to the USB drive in real time. If new data exceeds **500 MB**, the drive is immediately unmounted and locked until an overwrite password is entered.
- **Activity Logging:** Logs all USB insertions, authentication attempts, and threshold breaches to `transfer_log.txt`.

## Prerequisites
Install the required system tools:
```bash
sudo apt update && sudo apt install -y zenity psmisc udisks2
```

## Setup

1. **Make the script executable:**
```bash
chmod +x usb_monitor.sh
```

2. **Create your password hashes:**
Generate SHA-256 hashes for both the standard access password and the 500 MB overwrite password:
```bash
printf '%s' 'YourAccessPassword' | sha256sum | awk '{print $1}' > password.hash
printf '%s' 'YourOverwritePassword' | sha256sum | awk '{print $1}' > overwrite.hash
```

3. **Whitelist trusted USB drives (Optional):**
Find your USB drive's UUID:
```bash
lsblk -no NAME,TRAN,UUID
```
Add the UUID to `whitelist.txt`:
```bash
echo "YOUR-USB-UUID" >> whitelist.txt
```

## Usage
Run the script with `sudo` (required for mounting and unmounting drives):
```bash
sudo ./usb_monitor.sh
```

## Files
- `usb_monitor.sh` - Main monitoring script.
- `whitelist.txt` - List of approved USB partition UUIDs (one per line).
- `password.hash` - SHA-256 hash for mounting untrusted USB drives.
- `overwrite.hash` - SHA-256 hash for bypassing the 500 MB transfer limit.
- `transfer_log.txt` - Auto-generated log file of all events.
