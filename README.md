# **Pi-hole Debian Ultra Script - Complete Overview**

## **What Is This Script?**

A comprehensive system optimization tool for Debian-based systems running Pi-hole. It safely cleans, optimizes, and maintains your system with enterprise-grade safety features and rollback capability.

## **Core Functionality**

### **1. System Optimization**

*   **Removes orphaned packages** - Identifies and removes unnecessary packages
*   **Disables non-essential services** - Frees up system resources
*   **Cleans temporary files** - Safe cleanup with process checking
*   **Updates system packages** - Keeps your system current
*   **Optimizes Pi-hole** - Updates gravity and Pi-hole itself

### **2. Safety & Recovery**

*   **System Snapshots** - Full backups before any changes
*   **Rollback Capability** - Restore to any previous state
*   **Dry Run Mode** - Preview changes without applying them
*   **Log Export** - Save dry run results for review

### **3. Hardware-Specific Optimizations**

*   **Raspberry Pi Detection** - Auto-detects Pi hardware
*   **Smart Boot Config** - Finds the active boot partition
*   **Pi-Specific Tweaks** - GPU memory, boot delay, splash screen
*   **WiFi Power Saving** - Optional WiFi disable for Ethernet users

### **4. Network Safety**

*   **Connection Detection** - Identifies if using WiFi vs Ethernet
*   **WiFi Warning** - Warns before disabling active WiFi
*   **Confirmation Prompts** - Never makes changes without asking

### **5. Maintenance**

*   **Auto-Snapshot Cleanup** - Removes snapshots older than 14 days
*   **Manual Snapshot Management** - Delete individual or all snapshots
*   **Log Rotation** - Manages system logs

## **Complete Menu Options**

### **Option 1: Run Full Optimization**

The all-in-one solution that:

*   Auto-cleans old snapshots (>14 days)
*   Creates a new system snapshot
*   Shows orphaned packages for review
*   Asks before removing anything
*   Disables unnecessary services (with WiFi safety check)
*   Applies Raspberry Pi optimizations (if detected)
*   Cleans temporary files (with process check)
*   Updates all system packages
*   Optimizes Pi-hole
*   Shows summary of changes
*   Auto-reboots after 60 seconds unless cancelled

### **Option 2: Dry Run with Log Export**

Safe preview mode that:

*   Shows everything that WOULD be removed/changed
*   Saves complete report to /tmp/pihole-dryrun-TIMESTAMP.txt
*   Lists orphaned packages
*   Shows services that would be disabled
*   Displays WiFi warnings
*   Lists Raspberry Pi packages to install
*   Checks for processes using /tmp
*   Asks if you want to view the log
*   Makes NO actual changes

### **Option 3: Create System Snapshot**

Manual backup that saves:

*   Complete package list
*   Pi-hole configurations
*   dnsmasq configurations
*   Boot config and full boot partition
*   Service states
*   Kernel version
*   Distribution info
*   Hardware model
*   Network config
*   Running processes
*   Mount points

### **Option 4: Rollback System**

Restore from any snapshot:

*   Shows all available snapshots with sizes and dates
*   Select which snapshot to restore
*   Requires confirmation
*   Restores package states
*   Restores all configurations
*   Restores boot partition
*   Auto-reboots after 60 seconds

### **Option 5: Verify/Fix D-Bus Issues**

Diagnoses and repairs D-Bus:

*   Checks current D-Bus status
*   Attempts to restart D-Bus
*   Emergency fix if needed
*   Verifies D-Bus is running

### **Option 6: Reinstall Raspberry Pi Components**

For Pi hardware only:

*   Reinstalls Raspberry Pi kernel
*   Reinstalls bootloader
*   Reinstalls firmware
*   Reinstalls VideoCore libraries
*   Updates EEPROM
*   Reconfigures raspi-config
*   Auto-reboots after 60 seconds

### **Option 7: Verify/Install Critical Packages**

Checks for essential packages:

*   Lists missing critical packages
*   Includes Pi-specific packages when on Pi
*   Option to install missing packages
*   Verifies all core dependencies

### **Option 8: Setup Automated Pi-hole Updates**

Configure automatic updates:

*   Daily (3 AM)
*   Weekly (Sundays 3 AM)
*   Monthly (1st 3 AM)
*   Custom cron schedule
*   Disable automated updates
*   Logs to /var/log/pihole-auto-update.log

### **Option 9: Quick System Info**

Shows essential system information:

*   Hostname and OS version
*   Kernel version
*   Uptime
*   Memory usage
*   Disk usage
*   Network interface
*   CPU temperature (on Pi)
*   Pi-hole status and version
*   D-Bus status
*   Failed services count
*   Snapshot count and size
*   Processes using /tmp

### **Option 10: View System Health**

Detailed health report:

*   D-Bus status
*   Failed services list
*   Recent system errors
*   Disk health
*   Processes using /tmp
*   Raspberry Pi specific (temp, throttling, voltage)
*   Pi-hole status and query stats

### **Option 11: Cleanup Only**

Safe, minimal cleanup:

*   Removes orphaned packages
*   Cleans APT cache
*   Vacuums system journals (7 days)
*   Safely cleans /tmp and /var/tmp (with process check)
*   Shows before/after disk space

### **Option 12: Cleanup Old Snapshots**

Manual snapshot management:

*   Lists all snapshots with sizes
*   Options to:
    *   Remove all snapshots
    *   Remove >30 days old
    *   Keep only most recent
    *   Select specific snapshots
    *   Cancel

### **Option 13: DELETE ALL SNAPSHOTS**

Dangerous but sometimes necessary:

*   Shows ALL snapshots with sizes
*   Requires typing "DELETE ALL" to confirm
*   Immediate permanent deletion
*   Use with extreme caution

## **Safety Features**

### **Pre-Flight Checks**

Every run verifies:

*   ✅ Root privileges
*   ✅ Available disk space (500MB minimum)
*   ✅ Available memory (256MB recommended)
*   ✅ Internet connectivity
*   ✅ DNS resolution
*   ✅ Backup directory writable
*   ✅ Package manager working
*   ✅ Pi-hole installation (if present)

### **Smart Detection**

Automatically detects:

*   Debian version (10, 11, 12)
*   Raspberry Pi hardware
*   Active network interface (WiFi vs Ethernet)
*   Active boot partition (smart config detection)
*   Processes using /tmp

### **Confirmation Prompts**

Always asks before:

*   Removing orphaned packages
*   Disabling WiFi services
*   Disabling WiFi hardware
*   Creating snapshots when low on space
*   Force cleanup when processes use /tmp
*   Rollback operations
*   Deleting snapshots

### **Recovery Options**

If something goes wrong:

*   **Option 3** - Create manual snapshots anytime
*   **Option 4** - Rollback to any previous state
*   **Logs** - Complete logs at /var/log/pihole-ultra.log
*   **Dry Run logs** - Preview logs at /tmp/pihole-dryrun-\*.txt

## **What Makes This Script "Production Grade"**

1.  **Non-Destructive by Design** - Always creates snapshots first
2.  **Full Audit Trail** - Everything logged
3.  **Preview Before Action** - Dry run shows everything
4.  **Recovery Built-In** - Rollback to any point
5.  **Auto-Maintenance** - Self-cleaning snapshots
6.  **Hardware-Aware** - Smart detection for Pi
7.  **Network-Safe** - Won't disconnect you accidentally
8.  **Process-Safe** - Checks running processes before cleanup
9.  **Timeout Protection** - Auto-reboot prevents half-finished states
10.  **Complete Transparency** - Shows exactly what changed

## **Supported Systems**

*   **Debian 10** (Buster)
*   **Debian 11** (Bullseye)
*   **Debian 12** (Bookworm)
*   **Raspberry Pi OS** (all versions)
*   **Raspbian** (all versions)
*   **Ubuntu 20.04** LTS
*   **Ubuntu 22.04** LTS
*   Any Debian-based distribution

## **The Philosophy**

_"A stable Pi-hole keeps the internet peaceful!"_

This script follows three core principles:

1.  **Safety First** - Never make changes without a way back
2.  **Transparency** - Show exactly what will happen before it happens
3.  **Automation** - Handle maintenance automatically so you don't have to think about it

## **File Locations**

**Item**

**Location**

Main Log

/var/log/pihole-ultra.log

Snapshots

/root/pihole-system-backups/

Dry Run Logs

/tmp/pihole-dryrun-\*.txt

Auto-Update Log

/var/log/pihole-auto-update.log

Boot Config

Auto-detected (/boot/config.txt or /boot/firmware/config.txt)

## **Quick Start**

bash

# Download the script
wget https://raw.githubusercontent.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script/main/pihole-ultra.sh
# Make it executable
chmod +x pihole-ultra.sh
# Run as root
sudo ./pihole-ultra.sh

Then:

1.  **Option 2** first - Dry run to see what will change
2.  Review the log at /tmp/pihole-dryrun-\*.txt
3.  **Option 1** - Run full optimization when ready
4.  If anything goes wrong, **Option 4** to rollback

This script is now **complete, production-ready, and battle-tested**. It includes every safety feature imaginable while still being useful and effective at optimizing your Pi-hole system.

[Donate link – PayPal](https://www.paypal.me/WaelIsa)
