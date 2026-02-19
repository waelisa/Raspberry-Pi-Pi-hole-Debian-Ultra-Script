# **🛡️ Raspberry Pi Ultra Script**

**Unlike basic cleanup scripts, "Ultra" focuses on stability, hardware safety, and easy recovery.

Developed by [Wael Isa](https://github.com/waelisa).

## **✨ Key Features**

*   **🚀 Performance Optimization:** Safely removes Desktop bloatware and disables unneeded background services (Bluetooth, WiFi-matching, etc.) to free up RAM and CPU.
*   **📸 Snapshot & Rollback:** Automatically backs up your system state (package lists and configs) before making changes. Restore your system in one click if something goes wrong.
*   **🛡️ "Anti-Brick" Protection:** Includes a hardcoded list of protected Raspberry Pi firmware and kernel packages that the script will never touch.
*   **🔧 D-Bus Repair:** Built-in tools to verify and fix D-Bus communication, a common failure point in headless Debian 12 setups.
*   **📡 Intelligence:** Checks if you are connected via WiFi before disabling wireless services to prevent accidental lockouts.
*   **📅 Automated Maintenance:** Easily schedule Pi-hole Gravity updates via automated cron jobs.

## **🚀 Quick Start (One-Liner)**

To run the script directly on your Raspberry Pi, use the following command:

Bash

wget -qO pihole-ultra.sh https://raw.githubusercontent.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script/main/pihole-ultra.sh && chmod +x pihole-ultra.sh && sudo ./pihole-ultra.sh

## **🛠️ Menu Options**

When you run the script, you will be presented with a professional management menu:

1.  **Run Full Optimization:** The "all-in-one" choice. Creates a snapshot, removes bloat, and optimizes services.
2.  **Dry Run (Test):** See exactly what would be removed without actually touching any files.
3.  **Create System Snapshot:** Manually save your current package list and Pi-hole configurations.
4.  **Rollback System:** Restore a previous state from your saved snapshots.
5.  **Verify/Fix D-Bus:** Diagnoses and repairs system bus issues.
6.  **System Health View:** A dashboard showing real-time CPU, RAM, and Disk usage.

## **📋 Requirements**

*   **Hardware:** Raspberry Pi (any model).
*   **OS:** Debian 12 (Bookworm) — _Standard or Lite_.
*   **Permissions:** Must be run with sudo privileges.
*   **Disk Space:** Minimum 500MB free (for snapshots and safety).

## **📂 Logs & Backups**

*   **Logs:** All actions are logged to /var/log/pihole-ultra.log.
*   **Backups:** Snapshots are stored securely in /root/pihole-system-backups/.

## **⚖️ License**

Distributed under the MIT License. See LICENSE for more information.

## **🤝 Contributing**

If you have suggestions for new "protected packages" or performance tweaks, feel free to open an issue or submit a pull request!

1.  Fork the Project
2.  Create your Feature Branch (git checkout -b feature/AmazingFeature)
3.  Commit your Changes (git commit -m 'Add some AmazingFeature')
4.  Push to the Branch (git push origin feature/AmazingFeature)
5.  Open a Pull Request

[Donate link – PayPal](https://www.paypal.me/WaelIsa)
