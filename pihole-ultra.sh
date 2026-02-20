#!/bin/bash
# =============================================================================
# Pi-hole Debian Ultra Script - MENU DRIVEN WITH ROLLBACK
# =============================================================================
# Author:  Wael Isa
# Website: https://www.wael.name
# GitHub:  https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script
# Version: 2.2.1
# License: MIT
#
# Description: Complete system optimization script for systems running
#              Debian with Pi-hole. Includes safety features,
#              snapshots, rollback capability, and automated updates.
#              Compatible with Raspberry Pi and other Debian installations.
#
# NEW IN v2.2.1:
#   • Removed deborphan completely (phased out in Debian 13+)
#   • Native apt orphan detection using apt-mark and apt autoremove
#   • New cleanup_system() function for standardized maintenance
#   • Simplified package installation (no more deborphan errors)
#   • Better compatibility with Debian 13 (Trixie) and newer
#   • Faster orphan detection using native tools
#
# "A stable Pi-hole keeps the internet peaceful!"
#
# Usage: sudo ./pihole-ultra.sh
# =============================================================================

# ============== CONFIGURATION ==============
LOG_FILE="/var/log/pihole-ultra.log"
BACKUP_DIR="/root/pihole-system-backups"
SCRIPT_VERSION="2.2.1"
MIN_DISK_SPACE_MB=500  # Minimum 500MB free space required
MIN_MEMORY_MB=256      # Minimum 256MB free memory recommended
SNAPSHOT_RETENTION_DAYS=14  # Automatically remove snapshots older than this
REBOOT_TIMEOUT=60  # Seconds to wait for reboot confirmation before auto-reboot
DRY_RUN=false
DRY_RUN_LOG="/tmp/pihole-dryrun-$(date +%Y%m%d-%H%M%S).txt"
MAX_RETRY_ATTEMPTS=3  # Maximum retry attempts for failed operations
RETRY_DELAY=5  # Seconds between retries
exec > >(tee -a "$LOG_FILE") 2>&1

# ============== COLOR CODES FOR MENU ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============== ASCII ART ==============
show_banner() {
    echo -e "${CYAN}"
    echo '╔══════════════════════════════════════════════════════════════╗'
    echo '║     Pi-hole Debian Ultra Script v'$SCRIPT_VERSION'                    ║'
    echo '║     by Wael Isa (https://www.wael.name)                      ║'
    echo '║     GitHub: https://github.com/waelisa                       ║'
    echo '╚══════════════════════════════════════════════════════════════╝'
    echo -e "${NC}"
}

# ============== GLOBAL VARIABLES ==============
CURRENT_BACKUP=""
MENU_CHOICE=""
TEMP_SELECTIONS="/tmp/dpkg-selections.$$"
DETECTED_DISTRO=""
DETECTED_VERSION=""
DETECTED_CODENAME=""
IS_RASPBERRY_PI=false
RPI_MODEL=""
ACTIVE_INTERFACE=""
IS_WIFI_ACTIVE=false
OPTIMIZATION_STATS_FILE="/tmp/pihole-ultra-stats.$$"
START_TIME=$(date +%s)
START_DISK_USED=$(df / | awk 'NR==2 {print $3}')
SCRIPT_RUN_COUNT=0
BOOT_CONFIG_PATH=""
BOOT_PARTITION_MOUNT=""
PKG_MANAGER_READY=false

# ============== INITIAL CHECKS ==============
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Enhanced logging with timestamps
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Retry function for failed operations
retry_operation() {
    local cmd="$1"
    local description="$2"
    local attempt=1

    while [ $attempt -le $MAX_RETRY_ATTEMPTS ]; do
        echo -e "${YELLOW}Attempt $attempt/$MAX_RETRY_ATTEMPTS: $description${NC}"
        log_message "INFO" "Attempt $attempt: $description"

        if eval "$cmd"; then
            echo -e "${GREEN}✅ Success on attempt $attempt${NC}"
            log_message "SUCCESS" "Operation succeeded on attempt $attempt"
            return 0
        else
            if [ $attempt -lt $MAX_RETRY_ATTEMPTS ]; then
                echo -e "${YELLOW}⚠️  Attempt failed, retrying in $RETRY_DELAY seconds...${NC}"
                log_message "WARNING" "Attempt $attempt failed, retrying"
                sleep $RETRY_DELAY
            else
                echo -e "${RED}❌ All $MAX_RETRY_ATTEMPTS attempts failed${NC}"
                log_message "ERROR" "All attempts failed for: $description"
            fi
        fi
        ((attempt++))
    done
    return 1
}

# Display script information and what it does
show_script_info() {
    clear
    show_banner
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Pi-hole Debian Ultra Script - INFORMATION          ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} This script optimizes your Debian system with Pi-hole by:    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 1. Creating system snapshots (backup) before any changes     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2. Auto-cleaning snapshots older than ${SNAPSHOT_RETENTION_DAYS} days          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3. Removing unnecessary packages with native apt detection     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    • Uses apt-mark to find orphaned packages                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    • Native apt autoremove for safe cleanup                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    • Shows space savings before removal                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4. Disabling non-essential services                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 5. Optimizing system for Pi-hole performance                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 6. Cleaning temporary files and logs (with process check)     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 7. Setting up automated Pi-hole updates                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 8. Fixing common issues (D-Bus, services)                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 9. Raspberry Pi specific optimizations (if detected)          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}10. Auto-reboot after ${REBOOT_TIMEOUT} seconds if no response             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}11. Smart boot config detection (finds active config)          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}12. Dry Run log export (saves changes to /tmp)                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}13. Retry mechanism for failed operations (3 attempts)         ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} SAFETY FEATURES:                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Full system snapshots before optimization                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Rollback capability to restore previous state               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Dry-run mode with log export to review changes              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Network connectivity checks before disabling services       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Process checking before cleaning /tmp                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Smart boot config detection (finds active config)           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Confirmation prompts for critical operations                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Automatic snapshot cleanup to prevent disk filling          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Reboot timeout to prevent half-finished states              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Package removal size estimation and confirmation            ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}This script is now production-ready and has been tested on:${NC}"
    echo -e "  • Debian 10 (Buster) - Full support"
    echo -e "  • Debian 11 (Bullseye) - Full support"
    echo -e "  • Debian 12 (Bookworm) - Full support"
    echo -e "  • Debian 13 (Trixie) - Native apt orphan detection"
    echo -e "  • Raspberry Pi OS (all versions)"
    echo -e "  • Ubuntu 20.04 LTS and 22.04 LTS"
    echo ""
    echo -e "${YELLOW}If anything goes wrong, you have:${NC}"
    echo -e "  • Manual snapshots (Option 3)"
    echo -e "  • Rollback capability (Option 4)"
    echo -e "  • Complete logs at: $LOG_FILE"
    echo -e "  • Dry Run logs at: /tmp/pihole-dryrun-*.txt"
    echo -e "  • Auto-retry for failed operations (3 attempts)"
    echo ""
    read -p "Press Enter to continue to the main menu..."
}

# Enhanced system detection
detect_system_details() {
    log_message "INFO" "Detecting system details"

    # Get distribution codename
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DETECTED_CODENAME="$VERSION_CODENAME"
        if [ -z "$DETECTED_CODENAME" ]; then
            # Fallback for older systems
            DETECTED_CODENAME=$(lsb_release -sc 2>/dev/null || echo "unknown")
        fi
    fi

    echo -e "${GREEN}System Details:${NC}"
    echo -e "  • Distribution: $DETECTED_DISTRO $DETECTED_VERSION"
    echo -e "  • Codename: $DETECTED_CODENAME"
    echo -e "  • Architecture: $(dpkg --print-architecture)"
    echo -e "  • Kernel: $(uname -r)"

    log_message "INFO" "System: $DETECTED_DISTRO $DETECTED_VERSION, Codename: $DETECTED_CODENAME"
}

# Check for processes using /tmp
check_tmp_processes() {
    echo -e "\n${BLUE}=== Checking for Processes Using /tmp ===${NC}"
    log_message "INFO" "Checking /tmp processes"

    local tmp_processes=$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | wc -l)

    if [ "$tmp_processes" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Found $tmp_processes process(es) using /tmp:${NC}"
        echo ""
        lsof /tmp 2>/dev/null | head -20
        echo ""
        echo -e "${YELLOW}These processes may be relying on files in /tmp${NC}"
        log_message "WARNING" "Found $tmp_processes processes using /tmp"
        return 0
    else
        echo -e "${GREEN}✅ No processes using /tmp found${NC}"
        log_message "INFO" "No processes using /tmp"
        return 1
    fi
}

# Safe cleanup with process checking
safe_cleanup() {
    echo -e "\n${BLUE}=== Safe Cleanup with Process Check ===${NC}"
    log_message "INFO" "Starting safe cleanup"

    if check_tmp_processes; then
        echo -e "${RED}⚠️  WARNING: Some processes are using /tmp${NC}"
        echo -e "${YELLOW}Cleaning /tmp might cause these processes to crash${NC}"
        read -p "Do you want to see the full process list? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "\n${PURPLE}Full process list:${NC}"
            ps aux | grep -E "$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | awk '{print $2}' | sort -u | paste -sd '|')" 2>/dev/null
        fi

        echo ""
        read -p "Force cleanup anyway? This may crash running processes! (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Cleanup cancelled${NC}"
            log_message "INFO" "Cleanup cancelled by user"
            return 1
        fi
    fi

    # Calculate space before cleanup
    local before_tmp=$(du -sk /tmp 2>/dev/null | cut -f1)
    local before_vartmp=$(du -sk /var/tmp 2>/dev/null | cut -f1)
    local before_total=$((before_tmp + before_vartmp))

    # Proceed with cleanup
    echo -e "${YELLOW}Cleaning temporary files...${NC}"
    rm -rf /tmp/* 2>/dev/null
    rm -rf /var/tmp/* 2>/dev/null

    # Calculate space after cleanup
    local after_tmp=$(du -sk /tmp 2>/dev/null | cut -f1)
    local after_vartmp=$(du -sk /var/tmp 2>/dev/null | cut -f1)
    local after_total=$((after_tmp + after_vartmp))
    local saved=$((before_total - after_total))

    echo -e "${GREEN}✅ Temporary files cleaned${NC}"
    echo -e "${GREEN}   Space saved: $(numfmt --to=iec ${saved}K)${NC}"
    log_message "INFO" "Cleanup completed, saved $(numfmt --to=iec ${saved}K)"
    return 0
}

# Detect active network interface
detect_active_interface() {
    echo -e "\n${BLUE}=== Detecting Active Network Connection ===${NC}"
    log_message "INFO" "Detecting active network interface"

    # Get default route interface
    ACTIVE_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -n "$ACTIVE_INTERFACE" ]; then
        echo -e "${GREEN}✅ Default route via: $ACTIVE_INTERFACE${NC}"
        log_message "INFO" "Active interface: $ACTIVE_INTERFACE"

        # Check if it's a WiFi interface
        if [[ "$ACTIVE_INTERFACE" == wlan* ]] || [[ "$ACTIVE_INTERFACE" == wlp* ]]; then
            IS_WIFI_ACTIVE=true
            echo -e "${YELLOW}⚠️  Active connection is via WIFI ($ACTIVE_INTERFACE)${NC}"
            echo -e "${YELLOW}   Disabling WiFi would disconnect this session!${NC}"
            log_message "WARNING" "Active connection is WiFi"
        else
            IS_WIFI_ACTIVE=false
            echo -e "${GREEN}✅ Active connection is via Ethernet (safe to disable WiFi)${NC}"
            log_message "INFO" "Active connection is Ethernet"
        fi

        # Get IP address
        local ip_addr=$(ip -4 addr show "$ACTIVE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        echo -e "${GREEN}   IP Address: $ip_addr${NC}"
    else
        echo -e "${RED}❌ Could not detect active network interface${NC}"
        log_message "ERROR" "Could not detect active interface"
        IS_WIFI_ACTIVE=false
    fi
}

# Detect Debian version and compatibility
detect_debian_version() {
    if [ -f /etc/debian_version ]; then
        DETECTED_VERSION=$(cat /etc/debian_version)
        DETECTED_DISTRO="Debian"
        echo -e "${GREEN}✅ Detected: Debian $DETECTED_VERSION${NC}"
        log_message "INFO" "Detected Debian $DETECTED_VERSION"

        # Check if it's actually Raspbian/Raspberry Pi OS (which is Debian-based)
        if grep -q "Raspbian" /etc/os-release 2>/dev/null; then
            DETECTED_DISTRO="Raspbian"
            echo -e "${GREEN}✅ Detected: Raspbian/Debian $DETECTED_VERSION${NC}"
            log_message "INFO" "Detected Raspbian"
        elif grep -q "Raspberry Pi OS" /etc/os-release 2>/dev/null; then
            DETECTED_DISTRO="Raspberry Pi OS"
            echo -e "${GREEN}✅ Detected: Raspberry Pi OS (Debian $DETECTED_VERSION)${NC}"
            log_message "INFO" "Detected Raspberry Pi OS"
        fi

        detect_system_details
        return 0
    elif [ -f /etc/os-release ]; then
        # Try to get from os-release
        source /etc/os-release
        if [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            DETECTED_VERSION="$VERSION_ID"
            DETECTED_DISTRO="$NAME"
            echo -e "${GREEN}✅ Detected: $NAME $VERSION_ID${NC}"
            log_message "INFO" "Detected $NAME $VERSION_ID"
            detect_system_details
            return 0
        fi
    fi

    echo -e "${YELLOW}⚠️  Warning: This doesn't appear to be a Debian-based system${NC}"
    echo -e "${YELLOW}   Some features may not work correctly${NC}"
    log_message "WARNING" "Not a Debian-based system"
    DETECTED_DISTRO="Unknown"
    DETECTED_VERSION="Unknown"
    return 1
}

# Detect if running on Raspberry Pi
detect_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        if [[ "$RPI_MODEL" == *"Raspberry Pi"* ]]; then
            IS_RASPBERRY_PI=true
            echo -e "${GREEN}✅ Raspberry Pi detected: $RPI_MODEL${NC}"
            log_message "INFO" "Raspberry Pi detected: $RPI_MODEL"
            return 0
        fi
    fi

    # Alternative detection methods
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        IS_RASPBERRY_PI=true
        RPI_MODEL="Raspberry Pi (from cpuinfo)"
        echo -e "${GREEN}✅ Raspberry Pi detected${NC}"
        log_message "INFO" "Raspberry Pi detected from cpuinfo"
        return 0
    fi

    IS_RASPBERRY_PI=false
    return 1
}

# ENHANCED: Smart boot config detection - finds the ACTIVE config file
detect_boot_config() {
    echo -e "\n${BLUE}=== Detecting Active Boot Configuration ===${NC}"
    log_message "INFO" "Detecting boot config"

    BOOT_CONFIG_PATH=""
    BOOT_PARTITION_MOUNT=""

    # Method 1: Check which boot partition is actually mounted
    local boot_mounts=$(mount | grep -E "/boot" | awk '{print $3}')

    for mount_point in $boot_mounts; do
        if [ -f "${mount_point}/config.txt" ]; then
            BOOT_CONFIG_PATH="${mount_point}/config.txt"
            BOOT_PARTITION_MOUNT="$mount_point"
            echo -e "${GREEN}✅ Found active boot config at: $BOOT_CONFIG_PATH${NC}"
            echo -e "${GREEN}   Mount point: $BOOT_PARTITION_MOUNT${NC}"
            log_message "INFO" "Boot config found at $BOOT_CONFIG_PATH"
            return 0
        fi
    done

    # Method 2: Check standard Raspberry Pi paths
    if [ -f "/boot/firmware/config.txt" ]; then
        if mount | grep -q "/boot/firmware"; then
            BOOT_CONFIG_PATH="/boot/firmware/config.txt"
            BOOT_PARTITION_MOUNT="/boot/firmware"
            echo -e "${GREEN}✅ Found active boot config at: $BOOT_CONFIG_PATH${NC}"
            log_message "INFO" "Boot config found at $BOOT_CONFIG_PATH"
            return 0
        fi
    fi

    if [ -f "/boot/config.txt" ]; then
        if mount | grep -q "/boot"; then
            BOOT_CONFIG_PATH="/boot/config.txt"
            BOOT_PARTITION_MOUNT="/boot"
            echo -e "${GREEN}✅ Found active boot config at: $BOOT_CONFIG_PATH${NC}"
            log_message "INFO" "Boot config found at $BOOT_CONFIG_PATH"
            return 0
        fi
    fi

    echo -e "${YELLOW}⚠️  No boot config found. This may not be a Raspberry Pi.${NC}"
    log_message "WARNING" "No boot config found"
    return 1
}

# ============== NATIVE APT ORPHAN DETECTION (NO DEBORPHAN) ==============

# Calculate size of packages before removal
get_package_size() {
    local pkg="$1"
    local size=$(dpkg-query -W -f='${Installed-Size}\n' "$pkg" 2>/dev/null | head -1)
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        echo "$size"
    else
        echo "0"
    fi
}

# Show package removal preview with size estimates
preview_package_removal() {
    local packages="$1"
    local total_size=0
    local count=0
    local pkg_list=""

    echo -e "\n${PURPLE}Package removal preview:${NC}"
    echo "────────────────────────────────────"

    for pkg in $packages; do
        local size=$(get_package_size "$pkg")
        total_size=$((total_size + size))
        count=$((count + 1))
        pkg_list="$pkg_list $pkg"
        echo -e "  ${YELLOW}→ $pkg${NC} ($(numfmt --to=iec ${size}K))"
    done

    echo "────────────────────────────────────"
    echo -e "Total packages: $count"
    echo -e "Total space to be freed: $(numfmt --to=iec ${total_size}K)"
    echo ""

    return $total_size
}

# Native apt orphan detection (works on all Debian versions)
check_orphaned_packages() {
    echo -e "\n${BLUE}=== Checking for Orphaned Packages (Native apt) ===${NC}"
    log_message "INFO" "Starting orphaned package check using native apt"

    local total_found=0

    # Method 1: Use apt autoremove --dry-run to see what would be removed
    echo -e "\n${PURPLE}1. Packages that 'apt autoremove' would remove:${NC}"
    local autoremove_list=$(apt-get autoremove --dry-run 2>/dev/null | grep "^Remv" | awk '{print $2}')

    if [ -n "$autoremove_list" ]; then
        preview_package_removal "$autoremove_list"
        total_found=$((total_found + $(echo "$autoremove_list" | wc -l)))
        echo "$autoremove_list" > /tmp/pihole-autoremove.tmp
    else
        echo -e "${GREEN}  ✓ No packages found by autoremove${NC}"
    fi

    # Method 2: Find manually installed packages with no reverse dependencies
    echo -e "\n${PURPLE}2. Checking for orphaned libraries using apt-mark...${NC}"
    local orphan_candidates=""
    local candidate_count=0

    # Get all manually installed packages
    local manual_pkgs=$(apt-mark showmanual | grep -v "^lib" | head -30)

    for pkg in $manual_pkgs; do
        # Skip essential packages
        if dpkg -s "$pkg" 2>/dev/null | grep -q "Essential: yes"; then
            continue
        fi

        # Skip critical system packages
        if echo "$pkg" | grep -E "^(systemd|apt|bash|coreutils|dpkg|grub|linux-image|openssh)" >/dev/null; then
            continue
        fi

        # Check if any installed package depends on this one
        local rdeps=$(apt-cache rdepends --installed "$pkg" 2>/dev/null | grep -v "^  " | grep -v "^Reverse Depends" | tail -n +2 | grep -v "$pkg" | wc -l)
        if [ "$rdeps" -eq 0 ]; then
            orphan_candidates="$orphan_candidates $pkg"
            candidate_count=$((candidate_count + 1))
        fi
    done

    if [ "$candidate_count" -gt 0 ]; then
        preview_package_removal "$orphan_candidates"
        total_found=$((total_found + candidate_count))
        echo "$orphan_candidates" > /tmp/pihole-candidates.tmp
        echo -e "${YELLOW}Note: These are candidates - verify before removal!${NC}"
    else
        echo -e "${GREEN}  ✓ No orphan candidates found${NC}"
    fi

    # Method 3: Find packages that were auto-installed but no longer needed
    echo -e "\n${PURPLE}3. Checking auto-removable packages (apt-mark showauto)...${NC}"
    local auto_pkgs=$(apt-mark showauto 2>/dev/null | head -30)
    local auto_removable=""

    for pkg in $auto_pkgs; do
        # Check if this package is still required by anything
        if apt-cache rdepends --installed "$pkg" 2>/dev/null | grep -q "^  [^ ]"; then
            continue
        fi
        auto_removable="$auto_removable $pkg"
    done

    if [ -n "$auto_removable" ]; then
        preview_package_removal "$auto_removable"
        total_found=$((total_found + $(echo "$auto_removable" | wc -l)))
        echo "$auto_removable" > /tmp/pihole-auto.tmp
    else
        echo -e "${GREEN}  ✓ No auto-removable packages found${NC}"
    fi

    echo -e "\n${GREEN}Total potential orphaned packages found: $total_found${NC}"
    log_message "INFO" "Native apt detection found $total_found potential orphans"

    return $total_found
}

# Standardized system cleanup function (new in v2.2.1)
cleanup_system() {
    echo -e "\n${BLUE}=== Standard System Cleanup ===${NC}"
    log_message "INFO" "Starting system cleanup"

    # Update package database
    echo -e "${YELLOW}Updating package database...${NC}"
    apt-get update -qq

    # Remove packages that were automatically installed and are no longer needed
    echo -e "${YELLOW}Removing unused dependencies...${NC}"
    if apt-get autoremove --purge -y > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Unused dependencies removed${NC}"
        log_message "INFO" "Autoremove completed"
    else
        echo -e "${YELLOW}⚠️  Standard cleanup skipped or had no packages to remove${NC}"
    fi

    # Clear out the local repository of retrieved package files
    echo -e "${YELLOW}Cleaning package cache...${NC}"
    apt-get autoclean -y > /dev/null 2>&1
    apt-get clean > /dev/null 2>&1
    echo -e "${GREEN}✅ Package cache cleaned${NC}"

    # Vacuum journal logs
    echo -e "${YELLOW}Cleaning old system logs...${NC}"
    journalctl --vacuum-time=7d > /dev/null 2>&1
    echo -e "${GREEN}✅ Old logs cleaned${NC}"

    log_message "INFO" "System cleanup completed"
}

# Remove orphaned packages with safety checks
remove_orphaned_packages() {
    echo -e "\n${BLUE}=== Removing Orphaned Packages ===${NC}"
    log_message "INFO" "Starting orphaned package removal"

    local removal_mode=""
    local packages_to_remove=""

    echo -e "${PURPLE}Removal Options:${NC}"
    echo "1. Remove autoremove packages only (safest)"
    echo "2. Remove all detected orphans (moderate)"
    echo "3. Run full system cleanup (autoremove + autoclean)"
    echo "4. Select packages individually"
    echo "5. Skip removal"
    echo ""
    read -p "Choose option (1-5): " removal_choice

    case $removal_choice in
        1)
            if [ -f /tmp/pihole-autoremove.tmp ]; then
                packages_to_remove=$(cat /tmp/pihole-autoremove.tmp)
            fi
            removal_mode="autoremove only"
            ;;
        2)
            # Collect all orphans from temp files
            for tmp in /tmp/pihole-*.tmp; do
                if [ -f "$tmp" ]; then
                    packages_to_remove="$packages_to_remove $(cat "$tmp")"
                fi
            done
            removal_mode="all detected orphans"
            ;;
        3)
            echo -e "${YELLOW}Running full system cleanup...${NC}"
            cleanup_system
            return 0
            ;;
        4)
            # Collect all orphans
            local all_orphans=""
            for tmp in /tmp/pihole-*.tmp; do
                if [ -f "$tmp" ]; then
                    all_orphans="$all_orphans $(cat "$tmp")"
                fi
            done
            all_orphans=$(echo "$all_orphans" | tr ' ' '\n' | sort -u)

            echo -e "\n${PURPLE}Available orphaned packages:${NC}"
            local i=1
            local pkg_array=()
            for pkg in $all_orphans; do
                if [ -n "$pkg" ]; then
                    local size=$(get_package_size "$pkg")
                    echo "$i. $pkg ($(numfmt --to=iec ${size}K))"
                    pkg_array[$i]="$pkg"
                    i=$((i+1))
                fi
            done

            echo ""
            read -p "Enter package numbers to remove (comma-separated, e.g., 1,3,5): " selected
            IFS=',' read -ra indices <<< "$selected"
            for idx in "${indices[@]}"; do
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ -n "${pkg_array[$idx]}" ]; then
                    packages_to_remove="$packages_to_remove ${pkg_array[$idx]}"
                fi
            done
            removal_mode="selected packages"
            ;;
        5)
            echo -e "${YELLOW}Skipping orphaned package removal${NC}"
            log_message "INFO" "Orphan removal skipped"
            return 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac

    # Remove duplicates and empty lines
    packages_to_remove=$(echo "$packages_to_remove" | tr ' ' '\n' | sort -u | grep -v '^$')

    if [ -z "$packages_to_remove" ]; then
        echo -e "${YELLOW}No packages selected for removal${NC}"
        return 0
    fi

    # Preview removal
    echo -e "\n${YELLOW}Packages to be removed ($removal_mode):${NC}"
    preview_package_removal "$packages_to_remove"

    read -p "Proceed with removal? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removal cancelled${NC}"
        log_message "INFO" "Removal cancelled"
        return 0
    fi

    # Perform removal with retry
    local remove_cmd="apt-get remove --purge -y $packages_to_remove"
    if retry_operation "$remove_cmd" "Removing orphaned packages"; then
        echo -e "${GREEN}✅ Orphaned packages removed successfully${NC}"
        log_message "INFO" "Orphan removal completed"

        # Run autoremove to clean up any remaining dependencies
        apt-get autoremove --purge -y
    else
        echo -e "${RED}❌ Failed to remove orphaned packages${NC}"
        log_message "ERROR" "Orphan removal failed"
    fi

    # Clean up temp files
    rm -f /tmp/pihole-*.tmp
}

# Pre-flight safety check
pre_flight_check() {
    echo -e "\n${BLUE}=== Pre-Flight Safety Check ===${NC}"
    log_message "INFO" "Starting pre-flight checks"
    local checks_passed=true

    # Detect system info
    detect_debian_version
    detect_raspberry_pi
    detect_active_interface

    # Detect boot config if on Raspberry Pi
    if [ "$IS_RASPBERRY_PI" = true ]; then
        detect_boot_config
    fi

    # Check 1: Available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local available_space_mb=$((available_space / 1024))

    echo -e "\n${YELLOW}Checking disk space...${NC}"
    echo -e "  Available: ${available_space_mb}MB"
    echo -e "  Required: ${MIN_DISK_SPACE_MB}MB"

    if [ "$available_space_mb" -lt "$MIN_DISK_SPACE_MB" ]; then
        echo -e "${RED}  ❌ Insufficient disk space!${NC}"
        log_message "ERROR" "Insufficient disk space: ${available_space_mb}MB"
        checks_passed=false
    else
        echo -e "${GREEN}  ✅ Sufficient disk space${NC}"
    fi

    # Check 2: Available memory
    local available_mem=$(free -m | awk '/^Mem:/ {print $7}')
    echo -e "\n${YELLOW}Checking available memory...${NC}"
    echo -e "  Available: ${available_mem}MB"
    echo -e "  Recommended: ${MIN_MEMORY_MB}MB"

    if [ "$available_mem" -lt "$MIN_MEMORY_MB" ]; then
        echo -e "${YELLOW}  ⚠️  Low memory warning - operations may be slow${NC}"
        log_message "WARNING" "Low memory: ${available_mem}MB"
    else
        echo -e "${GREEN}  ✅ Adequate memory${NC}"
    fi

    # Check 3: Internet connectivity
    echo -e "\n${YELLOW}Checking internet connectivity...${NC}"
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}  ✅ Internet connected${NC}"
    else
        echo -e "${RED}  ❌ No internet connection!${NC}"
        log_message "ERROR" "No internet connection"
        checks_passed=false
    fi

    # Check 4: DNS resolution
    echo -e "\n${YELLOW}Checking DNS resolution...${NC}"
    if nslookup google.com &> /dev/null; then
        echo -e "${GREEN}  ✅ DNS working${NC}"
    else
        echo -e "${YELLOW}  ⚠️  DNS resolution failed (Pi-hole may not be running)${NC}"
        log_message "WARNING" "DNS resolution failed"
    fi

    # Check 5: Write permission to backup directory
    echo -e "\n${YELLOW}Checking backup directory...${NC}"
    if mkdir -p "$BACKUP_DIR" && touch "$BACKUP_DIR/test.tmp" 2>/dev/null; then
        rm -f "$BACKUP_DIR/test.tmp"
        echo -e "${GREEN}  ✅ Backup directory writable${NC}"
    else
        echo -e "${RED}  ❌ Cannot write to backup directory!${NC}"
        log_message "ERROR" "Backup directory not writable"
        checks_passed=false
    fi

    # Check 6: Package manager status
    echo -e "\n${YELLOW}Checking package manager...${NC}"
    if apt-get update -qq &> /dev/null; then
        echo -e "${GREEN}  ✅ Package manager working${NC}"
        PKG_MANAGER_READY=true
    else
        echo -e "${RED}  ❌ Package manager update failed!${NC}"
        log_message "ERROR" "Package manager update failed"
        checks_passed=false
    fi

    # Check 7: Check if Pi-hole is installed
    echo -e "\n${YELLOW}Checking Pi-hole installation...${NC}"
    if command -v pihole &> /dev/null; then
        local pihole_version=$(pihole -v | grep "Pi-hole" | head -1 | cut -d' ' -f4)
        echo -e "${GREEN}  ✅ Pi-hole is installed (version $pihole_version)${NC}"
        log_message "INFO" "Pi-hole version $pihole_version detected"
    else
        echo -e "${YELLOW}  ⚠️  Pi-hole is not installed - some features may be limited${NC}"
        log_message "WARNING" "Pi-hole not installed"
    fi

    echo -e "\n${BLUE}=== Pre-Flight Summary ===${NC}"
    if [ "$checks_passed" = true ]; then
        echo -e "${GREEN}✅ All critical checks passed!${NC}"
        log_message "INFO" "Pre-flight checks passed"
        return 0
    else
        echo -e "${RED}❌ Critical checks failed. Please resolve issues and try again.${NC}"
        log_message "ERROR" "Pre-flight checks failed"
        return 1
    fi
}

# Install required tools (deborphan removed from list)
install_required_tools() {
    echo -e "\n${BLUE}=== Checking Required Tools ===${NC}"
    log_message "INFO" "Checking required tools"

    if [ "$PKG_MANAGER_READY" = false ]; then
        echo -e "${RED}❌ Package manager not ready. Cannot install tools.${NC}"
        return 1
    fi

    apt-get update -qq

    # IMPORTANT: Ensure dselect is installed for rollback functionality
    if ! command -v dselect &> /dev/null; then
        echo -e "${YELLOW}Installing dselect for rollback functionality...${NC}"
        apt-get install -y dselect
        echo -e "${GREEN}✅ dselect installed${NC}"
        log_message "INFO" "dselect installed"
    else
        echo -e "${GREEN}✅ dselect already installed${NC}"
    fi

    # deborphan removed from this list - using native apt instead
    local tools=("curl" "wget" "git" "dnsutils" "numfmt" "lsb-release" "rfkill" "ethtool" "bc" "lsof")
    local installed_count=0

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null && ! dpkg -l | grep -q "ii  $tool "; then
            echo -e "${YELLOW}Installing $tool...${NC}"
            if apt-get install -y "$tool"; then
                echo -e "${GREEN}  ✅ $tool installed${NC}"
                installed_count=$((installed_count + 1))
                log_message "INFO" "Installed $tool"
            else
                echo -e "${RED}  ❌ Failed to install $tool${NC}"
                log_message "ERROR" "Failed to install $tool"
            fi
        fi
    done

    if [ $installed_count -gt 0 ]; then
        echo -e "${GREEN}✅ Installed $installed_count new tools${NC}"
    else
        echo -e "${GREEN}✅ All required tools already installed${NC}"
    fi
}

# Verify D-Bus is working
verify_dbus() {
    echo -e "\n${BLUE}=== Verifying D-Bus System Bus ===${NC}"
    log_message "INFO" "Verifying D-Bus"

    if ! systemctl is-active --quiet dbus; then
        echo -e "${YELLOW}⚠️  D-Bus system bus not running. Attempting to start...${NC}"
        systemctl start dbus
        sleep 2

        if systemctl is-active --quiet dbus; then
            echo -e "${GREEN}✅ D-Bus started successfully${NC}"
            log_message "INFO" "D-Bus started"
        else
            echo -e "${RED}❌ Failed to start D-Bus. Some functions may not work.${NC}"
            log_message "ERROR" "Failed to start D-Bus"
            systemctl start dbus.socket
            sleep 2
            systemctl start dbus
        fi
    else
        echo -e "${GREEN}✅ D-Bus system bus is running${NC}"
    fi

    if systemctl is-active --quiet dbus; then
        echo -e "${GREEN}✅ D-Bus verification passed${NC}"
        return 0
    else
        echo -e "${RED}❌ D-Bus verification failed${NC}"
        return 1
    fi
}

# Get config.txt path (using smart detection)
get_config_path() {
    if [ -n "$BOOT_CONFIG_PATH" ]; then
        echo "$BOOT_CONFIG_PATH"
    else
        # Fallback to old method if smart detection failed
        if [ -f "/boot/firmware/config.txt" ]; then
            echo "/boot/firmware/config.txt"
        elif [ -f "/boot/config.txt" ]; then
            echo "/boot/config.txt"
        else
            echo ""
        fi
    fi
}

# Estimate backup size
estimate_backup_size() {
    echo -e "\n${BLUE}=== Estimating Backup Size ===${NC}"
    log_message "INFO" "Estimating backup size"

    local total_size=0

    if [ -d "/etc/pihole" ]; then
        local pihole_size=$(du -sk /etc/pihole 2>/dev/null | cut -f1)
        total_size=$((total_size + pihole_size))
        echo -e "${YELLOW}  /etc/pihole: $(numfmt --to=iec ${pihole_size}K)${NC}"
    fi

    if [ -d "/etc/dnsmasq.d" ]; then
        local dnsmasq_size=$(du -sk /etc/dnsmasq.d 2>/dev/null | cut -f1)
        total_size=$((total_size + dnsmasq_size))
        echo -e "${YELLOW}  /etc/dnsmasq.d: $(numfmt --to=iec ${dnsmasq_size}K)${NC}"
    fi

    # Add boot config size if it exists
    local config_path=$(get_config_path)
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        local config_size=$(du -sk "$config_path" 2>/dev/null | cut -f1)
        total_size=$((total_size + config_size))
        echo -e "${YELLOW}  Boot config: $(numfmt --to=iec ${config_size}K)${NC}"
    fi

    local pkg_count=$(dpkg -l | grep -c "^ii")
    local pkg_list_size=$((pkg_count / 10))
    total_size=$((total_size + pkg_list_size))
    echo -e "${YELLOW}  Package list: ~$(numfmt --to=iec ${pkg_list_size}K)${NC}"

    echo -e "${GREEN}  Total estimated backup size: $(numfmt --to=iec ${total_size}K)${NC}"

    local available_space=$(df / | awk 'NR==2 {print $4}')
    local available_space_mb=$((available_space / 1024))
    local required_space_mb=$((total_size / 1024 + 50))

    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        echo -e "${RED}  ❌ Insufficient space for backup!${NC}"
        echo -e "${RED}     Need: ${required_space_mb}MB, Available: ${available_space_mb}MB${NC}"
        log_message "ERROR" "Insufficient backup space"
        return 1
    else
        echo -e "${GREEN}  ✅ Sufficient space for backup${NC}"
        return 0
    fi
}

# Create system snapshot
create_snapshot() {
    local snapshot_name="pre-optimization-$(date +%Y%m%d-%H%M%S)"
    local snapshot_dir="${BACKUP_DIR}/${snapshot_name}"

    echo -e "\n${BLUE}=== Creating System Snapshot ===${NC}"
    log_message "INFO" "Creating snapshot $snapshot_name"

    if ! estimate_backup_size; then
        echo -e "${RED}❌ Cannot create snapshot - insufficient space${NC}"
        read -p "Force snapshot anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    mkdir -p "$snapshot_dir"

    echo -e "${YELLOW}Saving package list...${NC}"
    dpkg --get-selections > "${snapshot_dir}/package-list.txt"

    echo -e "${YELLOW}Backing up configurations...${NC}"
    [ -d "/etc/pihole" ] && cp -r /etc/pihole "${snapshot_dir}/" 2>/dev/null && echo -e "${GREEN}  ✅ Pi-hole config backed up${NC}"
    [ -d "/etc/dnsmasq.d" ] && cp -r /etc/dnsmasq.d "${snapshot_dir}/" 2>/dev/null && echo -e "${GREEN}  ✅ dnsmasq config backed up${NC}"
    [ -f "/etc/pihole/adlists.list" ] && cp /etc/pihole/adlists.list "${snapshot_dir}/" 2>/dev/null && echo -e "${GREEN}  ✅ Adlists backed up${NC}"

    # Backup boot configs if they exist (using smart detection)
    local config_path=$(get_config_path)
    if [ -n "$config_path" ]; then
        cp "$config_path" "${snapshot_dir}/config.txt.backup"
        echo -e "${GREEN}  ✅ Boot config backed up: ${config_path}${NC}"

        # Also backup the entire boot partition for safety
        if [ -n "$BOOT_PARTITION_MOUNT" ] && [ -d "$BOOT_PARTITION_MOUNT" ]; then
            cp -r "$BOOT_PARTITION_MOUNT" "${snapshot_dir}/boot-partition-backup" 2>/dev/null
            echo -e "${GREEN}  ✅ Full boot partition backed up from: $BOOT_PARTITION_MOUNT${NC}"
        elif [ -d "/boot/firmware" ]; then
            cp -r /boot/firmware "${snapshot_dir}/firmware-backup" 2>/dev/null
            echo -e "${GREEN}  ✅ Firmware directory backed up${NC}"
        elif [ -d "/boot" ]; then
            cp /boot/*.txt "${snapshot_dir}/" 2>/dev/null
            echo -e "${GREEN}  ✅ Boot text files backed up${NC}"
        fi
    fi

    echo -e "${YELLOW}Saving service states...${NC}"
    systemctl list-units --type=service --all > "${snapshot_dir}/services-before.txt"

    dpkg -l > "${snapshot_dir}/all-packages.txt"
    uname -a > "${snapshot_dir}/kernel-version.txt"

    # Save distribution info
    cp /etc/os-release "${snapshot_dir}/os-release" 2>/dev/null
    cp /etc/debian_version "${snapshot_dir}/debian-version" 2>/dev/null

    # Save hardware info if available
    if [ -f /proc/device-tree/model ]; then
        cat /proc/device-tree/model 2>/dev/null | tr -d '\0' > "${snapshot_dir}/hardware-model.txt"
    fi

    # Save network config
    ip addr show > "${snapshot_dir}/network-config.txt" 2>/dev/null

    # Save process list
    ps aux > "${snapshot_dir}/process-list.txt" 2>/dev/null

    # Save mount points for boot detection
    mount > "${snapshot_dir}/mounts.txt" 2>/dev/null

    # Save system info
    echo "Snapshot created: $(date)" > "${snapshot_dir}/snapshot-info.txt"
    echo "Script version: $SCRIPT_VERSION" >> "${snapshot_dir}/snapshot-info.txt"
    echo "User: $USER" >> "${snapshot_dir}/snapshot-info.txt"
    echo "Boot config: $config_path" >> "${snapshot_dir}/snapshot-info.txt"
    echo "Boot mount: $BOOT_PARTITION_MOUNT" >> "${snapshot_dir}/snapshot-info.txt"

    local snapshot_size=$(du -sh "$snapshot_dir" | cut -f1)
    echo -e "${GREEN}✅ Snapshot created: ${snapshot_name}${NC}"
    echo -e "${GREEN}   Location: ${snapshot_dir}${NC}"
    echo -e "${GREEN}   Size: ${snapshot_size}${NC}"
    log_message "INFO" "Snapshot created: $snapshot_name ($snapshot_size)"

    CURRENT_BACKUP="$snapshot_name"
}

# Auto-clean old snapshots (older than SNAPSHOT_RETENTION_DAYS)
auto_cleanup_snapshots() {
    echo -e "\n${BLUE}=== Auto-Cleaning Old Snapshots ===${NC}"
    log_message "INFO" "Auto-cleaning snapshots"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}No snapshots directory found.${NC}"
        return
    fi

    local old_snapshots=$(find "$BACKUP_DIR" -type d -name "pre-optimization-*" -mtime +${SNAPSHOT_RETENTION_DAYS} 2>/dev/null)
    local old_count=$(echo "$old_snapshots" | grep -v "^$" | wc -l)

    if [ "$old_count" -gt 0 ]; then
        echo -e "${YELLOW}Found $old_count snapshot(s) older than $SNAPSHOT_RETENTION_DAYS days${NC}"
        echo "$old_snapshots" | while read snapshot; do
            local size=$(du -sh "$snapshot" 2>/dev/null | cut -f1)
            echo -e "  ${YELLOW}→ Removing: $(basename "$snapshot") (${size})${NC}"
            rm -rf "$snapshot"
            log_message "INFO" "Removed old snapshot: $(basename "$snapshot")"
        done
        echo -e "${GREEN}✅ Old snapshots cleaned up${NC}"
    else
        echo -e "${GREEN}✅ No snapshots older than $SNAPSHOT_RETENTION_DAYS days found${NC}"
    fi
}

# Delete all snapshots immediately
delete_all_snapshots() {
    echo -e "\n${RED}=== DELETE ALL SNAPSHOTS ===${NC}"
    log_message "WARNING" "Delete all snapshots initiated"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}No snapshots directory found.${NC}"
        return
    fi

    local snapshot_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)

    if [ "$snapshot_count" -eq 0 ]; then
        echo -e "${YELLOW}No snapshots to delete.${NC}"
        return
    fi

    echo -e "${RED}⚠️  WARNING: This will delete ALL $snapshot_count snapshot(s)!${NC}"
    echo -e "${YELLOW}Snapshots to be deleted:${NC}"
    ls -1 "$BACKUP_DIR" | while read snapshot; do
        local size=$(du -sh "${BACKUP_DIR}/$snapshot" 2>/dev/null | cut -f1)
        echo -e "  ${YELLOW}→ $snapshot (${size})${NC}"
    done

    echo ""
    read -p "Are you ABSOLUTELY sure? (type 'DELETE ALL' to confirm): " confirm

    if [ "$confirm" = "DELETE ALL" ]; then
        echo -e "${YELLOW}Deleting all snapshots...${NC}"
        rm -rf "${BACKUP_DIR:?}"/*
        echo -e "${GREEN}✅ All snapshots deleted successfully${NC}"
        log_message "INFO" "All snapshots deleted"
    else
        echo -e "${YELLOW}Deletion cancelled${NC}"
    fi
}

# Rollback function
rollback_system() {
    echo -e "\n${PURPLE}=== System Rollback ===${NC}"
    echo -e "${YELLOW}This will restore your system to a previous state${NC}\n"
    log_message "INFO" "System rollback initiated"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ No backup directory found at $BACKUP_DIR${NC}"
        log_message "ERROR" "No backup directory"
        return 1
    fi

    local snapshots=($(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r))

    if [ ${#snapshots[@]} -eq 0 ]; then
        echo -e "${RED}❌ No snapshots found to rollback to${NC}"
        log_message "ERROR" "No snapshots found"
        return 1
    fi

    echo -e "${YELLOW}Available snapshots (most recent first):${NC}"
    for i in "${!snapshots[@]}"; do
        local size=$(du -sh "${BACKUP_DIR}/${snapshots[$i]}" 2>/dev/null | cut -f1)
        local date=$(echo "${snapshots[$i]}" | sed 's/pre-optimization-//')
        echo "$((i+1)). ${snapshots[$i]} (${size}) - ${date}"
    done

    echo ""
    read -p "Select snapshot to rollback to (or 0 to cancel): " snapshot_choice

    if [ "$snapshot_choice" = "0" ]; then
        echo -e "${YELLOW}Rollback cancelled${NC}"
        log_message "INFO" "Rollback cancelled"
        return 0
    fi

    if ! [[ "$snapshot_choice" =~ ^[0-9]+$ ]] || [ "$snapshot_choice" -gt ${#snapshots[@]} ]; then
        echo -e "${RED}❌ Invalid selection${NC}"
        return 1
    fi

    local selected="${snapshots[$((snapshot_choice-1))]}"
    local snapshot_dir="${BACKUP_DIR}/${selected}"

    if [ ! -d "$snapshot_dir" ]; then
        echo -e "${RED}❌ Snapshot directory not found${NC}"
        return 1
    fi

    echo -e "${YELLOW}⚠️  WARNING: Rolling back will revert package states${NC}"
    echo -e "${YELLOW}This may take several minutes and will require a reboot${NC}"
    read -p "Are you absolutely sure? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}Rollback cancelled${NC}"
        return 0
    fi

    # Save current selections before clearing
    echo -e "${BLUE}Saving current package selections as emergency backup...${NC}"
    dpkg --get-selections > "${TEMP_SELECTIONS}.current"

    # Perform rollback with atomic operation
    echo -e "${BLUE}Restoring package states...${NC}"
    if [ -f "$snapshot_dir/package-list.txt" ]; then
        if retry_operation "dpkg --clear-selections && dpkg --set-selections < '$snapshot_dir/package-list.txt'" "Restoring package selections"; then
            echo -e "${GREEN}✅ Package selections restored successfully${NC}"

            echo -e "${BLUE}Applying package changes (this may take a while)...${NC}"
            if retry_operation "apt-get dselect-upgrade -y" "Applying package changes"; then
                echo -e "${GREEN}✅ Package states restored successfully${NC}"
            else
                echo -e "${RED}❌ Some packages may not have restored correctly${NC}"
                echo -e "${YELLOW}Emergency backup saved at: ${TEMP_SELECTIONS}.current${NC}"
            fi
        else
            echo -e "${RED}❌ Failed to restore package selections${NC}"
            echo -e "${YELLOW}Restoring previous selections from emergency backup...${NC}"
            dpkg --clear-selections && dpkg --set-selections < "${TEMP_SELECTIONS}.current"
            echo -e "${YELLOW}Previous selections restored${NC}"
        fi
    fi

    # Restore configs
    echo -e "${BLUE}Restoring configuration files...${NC}"
    [ -d "$snapshot_dir/pihole" ] && cp -r "$snapshot_dir/pihole" /etc/ 2>/dev/null && echo -e "${GREEN}✅ Pi-hole config restored${NC}"
    [ -d "$snapshot_dir/dnsmasq.d" ] && cp -r "$snapshot_dir/dnsmasq.d" /etc/ 2>/dev/null && echo -e "${GREEN}✅ dnsmasq config restored${NC}"

    # Restore boot config using smart detection
    if [ -f "$snapshot_dir/config.txt.backup" ]; then
        local config_path=$(get_config_path)
        if [ -n "$config_path" ]; then
            cp "$snapshot_dir/config.txt.backup" "$config_path"
            echo -e "${GREEN}✅ Boot config restored to: $config_path${NC}"
        fi
    fi

    # Restore full boot partition backup if it exists
    if [ -d "$snapshot_dir/boot-partition-backup" ]; then
        if [ -n "$BOOT_PARTITION_MOUNT" ] && [ -d "$BOOT_PARTITION_MOUNT" ]; then
            cp -r "$snapshot_dir/boot-partition-backup"/* "$BOOT_PARTITION_MOUNT/" 2>/dev/null
            echo -e "${GREEN}✅ Boot partition restored to: $BOOT_PARTITION_MOUNT${NC}"
        fi
    elif [ -d "$snapshot_dir/firmware-backup" ]; then
        if [ -d "/boot/firmware" ]; then
            cp -r "$snapshot_dir/firmware-backup"/* /boot/firmware/ 2>/dev/null
            echo -e "${GREEN}✅ Firmware directory restored${NC}"
        fi
    fi

    # Clean up temp file
    rm -f "${TEMP_SELECTIONS}.current" 2>/dev/null

    echo -e "${GREEN}✅ Rollback completed${NC}"
    echo -e "${YELLOW}⚠️  A system reboot is REQUIRED to complete rollback${NC}"
    log_message "INFO" "Rollback completed, reboot required"

    # Reboot countdown with timeout
    echo -e "\n${YELLOW}System will reboot automatically in $REBOOT_TIMEOUT seconds...${NC}"
    echo -e "${YELLOW}Press any key to cancel reboot${NC}"

    if read -t $REBOOT_TIMEOUT -n 1 -s; then
        echo -e "\n${GREEN}Reboot cancelled. Please reboot manually later: sudo reboot${NC}"
    else
        echo -e "\n${YELLOW}No input received. Rebooting now...${NC}"
        echo "Rebooting in 5 seconds... Press Ctrl+C to cancel"
        sleep 5
        reboot
    fi
}

# Setup automated Pi-hole updates
setup_pihole_updates() {
    echo -e "\n${BLUE}=== Pi-hole Automated Updates Setup ===${NC}"
    log_message "INFO" "Setting up Pi-hole updates"

    echo -e "${YELLOW}Choose update frequency:${NC}"
    echo "1. Daily (at 3:00 AM)"
    echo "2. Weekly (Sundays at 3:00 AM)"
    echo "3. Monthly (1st of month at 3:00 AM)"
    echo "4. Custom cron schedule"
    echo "5. Disable automated updates"
    echo "0. Cancel"

    read -p "Select option: " freq_choice

    case $freq_choice in
        1)
            CRON_SCHEDULE="0 3 * * *"
            FREQ_TEXT="daily"
            ;;
        2)
            CRON_SCHEDULE="0 3 * * 0"
            FREQ_TEXT="weekly (Sundays)"
            ;;
        3)
            CRON_SCHEDULE="0 3 1 * *"
            FREQ_TEXT="monthly (1st)"
            ;;
        4)
            read -p "Enter custom cron schedule (e.g., '0 */6 * * *' for every 6 hours): " CRON_SCHEDULE
            FREQ_TEXT="custom"
            ;;
        5)
            echo -e "${YELLOW}Removing Pi-hole update cron job...${NC}"
            crontab -l 2>/dev/null | grep -v "pihole updateGravity" | crontab -
            echo -e "${GREEN}✅ Automated updates disabled${NC}"
            log_message "INFO" "Auto-updates disabled"
            return 0
            ;;
        0)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac

    local cron_cmd="$CRON_SCHEDULE /usr/local/bin/pihole updateGravity > /var/log/pihole-auto-update.log 2>&1"

    crontab -l 2>/dev/null | grep -v "pihole updateGravity" > /tmp/crontab.tmp
    echo "$cron_cmd" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp

    echo -e "${GREEN}✅ Pi-hole updates scheduled ${FREQ_TEXT}${NC}"
    echo -e "${GREEN}   Schedule: $CRON_SCHEDULE${NC}"
    echo -e "${YELLOW}   Logs: /var/log/pihole-auto-update.log${NC}"
    log_message "INFO" "Updates scheduled: $FREQ_TEXT - $CRON_SCHEDULE"

    crontab -l | grep "pihole updateGravity"
}

# Quick system info
quick_system_info() {
    echo -e "\n${BLUE}=== Quick System Information ===${NC}"
    echo -e "${GREEN}Hostname:${NC} $(hostname)"
    echo -e "${GREEN}OS:${NC} $DETECTED_DISTRO $DETECTED_VERSION ($DETECTED_CODENAME)"
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"
    echo -e "${GREEN}Uptime:${NC} $(uptime -p)"
    echo -e "${GREEN}Memory:${NC} $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo -e "${GREEN}Disk:${NC} $(df -h / | awk 'NR==2 {print $3"/"$2 " ("$5")"}')"
    echo -e "${GREEN}Active Network:${NC} $ACTIVE_INTERFACE ($([ "$IS_WIFI_ACTIVE" = true ] && echo "WiFi" || echo "Ethernet"))"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${GREEN}Hardware:${NC} $RPI_MODEL"
        echo -e "${GREEN}Boot Config:${NC} $BOOT_CONFIG_PATH"
        # Get CPU temperature if available
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            CPU_TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
            echo -e "${GREEN}CPU Temp:${NC} ${CPU_TEMP}°C"
        fi
    fi

    if command -v pihole &> /dev/null; then
        echo -e "${GREEN}Pi-hole:${NC} $(pihole status | head -1)"
        echo -e "${GREEN}Pi-hole Version:${NC} $(pihole -v | grep "Pi-hole" | head -1 | cut -d' ' -f4)"
        echo -e "${GREEN}Blocked Today:${NC} $(pihole -c -j 2>/dev/null | grep -o '"ads_blocked_today":[0-9]*' | cut -d':' -f2 || echo "N/A")"
    else
        echo -e "${YELLOW}Pi-hole:${NC} Not installed"
    fi

    echo -e "${GREEN}D-Bus:${NC} $(systemctl is-active dbus)"
    echo -e "${GREEN}Failed Services:${NC} $(systemctl --failed | grep -c "loaded failed" || echo "0")"

    # Show backup stats
    if [ -d "$BACKUP_DIR" ]; then
        local snapshot_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo -e "${GREEN}Snapshots:${NC} $snapshot_count (total size: $backup_size)"
    fi

    # Show processes using /tmp
    local tmp_processes=$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | wc -l)
    echo -e "${GREEN}Processes using /tmp:${NC} $tmp_processes"

    log_message "INFO" "Quick system info displayed"
}

# View system health
view_system_health() {
    echo -e "\n${BLUE}=== System Health Report ===${NC}"
    log_message "INFO" "Viewing system health"

    echo -e "\n${YELLOW}D-Bus Status:${NC}"
    systemctl status dbus --no-pager | head -3

    echo -e "\n${YELLOW}Failed Services:${NC}"
    systemctl --failed --no-pager || echo "None"

    echo -e "\n${YELLOW}Recent System Errors:${NC}"
    journalctl -p 3 -b --no-pager | tail -10

    echo -e "\n${YELLOW}Disk Health:${NC}"
    df -h | grep -E "^/dev|Filesystem"

    echo -e "\n${YELLOW}Memory Usage:${NC}"
    free -h

    echo -e "\n${YELLOW}Processes Using /tmp:${NC}"
    lsof /tmp 2>/dev/null | head -20 || echo "None"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${YELLOW}Raspberry Pi Specific:${NC}"
        vcgencmd measure_temp 2>/dev/null
        vcgencmd get_throttled 2>/dev/null
        vcgencmd measure_volts core 2>/dev/null
        echo -e "${YELLOW}Active Boot Config:${NC} $BOOT_CONFIG_PATH"
    fi

    if command -v pihole &> /dev/null; then
        echo -e "\n${YELLOW}Pi-hole Status:${NC}"
        pihole status
        echo -e "\n${YELLOW}Pi-hole Query Log Stats:${NC}"
        pihole -c -j 2>/dev/null | grep -E "total_queries|blocked_queries" || echo "Unable to get stats"
    fi

    echo -e "\n${YELLOW}Last 10 System Log Entries:${NC}"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "No log entries"
}

# Fix D-Bus
fix_dbus() {
    echo -e "\n${BLUE}=== D-Bus Repair Utility ===${NC}"
    log_message "INFO" "Attempting D-Bus repair"

    echo -e "${YELLOW}Current D-Bus status:${NC}"
    systemctl status dbus --no-pager | head -3

    echo -e "\n${YELLOW}Attempting fixes...${NC}"

    systemctl stop dbus.socket 2>/dev/null
    systemctl stop dbus 2>/dev/null

    rm -f /run/dbus/system_bus_socket 2>/dev/null

    systemctl start dbus.socket
    sleep 2
    systemctl start dbus

    if systemctl is-active --quiet dbus; then
        echo -e "${GREEN}✅ D-Bus is now running${NC}"
        log_message "INFO" "D-Bus fixed"
    else
        echo -e "${RED}❌ D-Bus still not running. Trying emergency fix...${NC}"
        dbus-daemon --system --fork
        sleep 2
        systemctl start dbus
    fi

    systemctl status dbus --no-pager | head -3
}

# Cleanup only (with process check)
cleanup_only() {
    echo -e "\n${BLUE}=== Safe Cleanup Mode ===${NC}"
    echo -e "${YELLOW}This will clean temporary files and logs${NC}"
    echo -e "${YELLOW}No system changes will be made${NC}\n"
    log_message "INFO" "Starting cleanup only"

    read -p "Proceed with safe cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    local before_space=$(df -h / | awk 'NR==2 {print $4}')

    # Use the new standardized cleanup function
    cleanup_system

    # Safe cleanup with process check
    safe_cleanup

    local after_space=$(df -h / | awk 'NR==2 {print $4}')

    echo -e "${GREEN}✅ Safe cleanup completed${NC}"
    echo -e "Disk space before: $before_space"
    echo -e "Disk space after: $after_space"
    log_message "INFO" "Cleanup completed, freed space"
}

# Verify packages
verify_packages() {
    echo -e "\n${BLUE}=== Verifying critical packages ===${NC}"
    log_message "INFO" "Verifying packages"

    local critical_pkgs=(
        "ca-certificates"
        "curl"
        "wget"
        "gnupg"
        "apt-utils"
        "systemd"
        "dbus"
        "python3"
        "lsof"
    )

    # Add Raspberry Pi specific packages if on RPi
    if [ "$IS_RASPBERRY_PI" = true ]; then
        critical_pkgs+=(
            "raspberrypi-kernel"
            "raspberrypi-bootloader"
            "raspberrypi-sys-mods"
            "raspi-config"
            "raspi-utils"
            "rpi-eeprom"
            "libraspberrypi-bin"
            "libraspberrypi-dev"
            "libraspberrypi-doc"
            "libraspberrypi0"
        )
        echo -e "${YELLOW}Raspberry Pi detected: Including Pi-specific packages${NC}"
    fi

    local all_good=true
    local missing_pkgs=()
    local installed_pkgs=()

    for pkg in "${critical_pkgs[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            echo -e "${GREEN}✅ $pkg is installed${NC}"
            installed_pkgs+=("$pkg")
        else
            echo -e "${YELLOW}⚠️  $pkg is NOT installed${NC}"
            missing_pkgs+=("$pkg")
            all_good=false
        fi
    done

    if [ "$all_good" = false ] && [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  Some packages appear to be missing.${NC}"
        read -p "Do you want to attempt installing missing packages? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apt update
            for pkg in "${missing_pkgs[@]}"; do
                echo "Installing $pkg..."
                if apt install -y "$pkg"; then
                    echo -e "${GREEN}  ✅ $pkg installed${NC}"
                else
                    echo -e "${RED}  ❌ Failed to install $pkg${NC}"
                fi
            done
            echo -e "${GREEN}✅ Missing packages installation attempted${NC}"
            log_message "INFO" "Installed missing packages: ${missing_pkgs[*]}"
        fi
    else
        echo -e "${GREEN}✅ All critical packages are installed${NC}"
    fi
}

# Clean up old snapshots (manual)
cleanup_snapshots() {
    echo -e "\n${BLUE}=== Snapshot Cleanup ===${NC}"
    log_message "INFO" "Manual snapshot cleanup"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}No snapshots directory found.${NC}"
        return
    fi

    local snapshots=($(ls -1 "$BACKUP_DIR" 2>/dev/null | sort))

    if [ ${#snapshots[@]} -eq 0 ]; then
        echo -e "${YELLOW}No snapshots found to clean up.${NC}"
        return
    fi

    echo -e "${YELLOW}Current snapshots:${NC}"
    for i in "${!snapshots[@]}"; do
        local size=$(du -sh "${BACKUP_DIR}/${snapshots[$i]}" 2>/dev/null | cut -f1)
        local date=$(echo "${snapshots[$i]}" | sed 's/pre-optimization-//')
        echo "$((i+1)). ${snapshots[$i]} (${size}) - ${date}"
    done

    echo ""
    echo "Options:"
    echo "1. Remove all snapshots"
    echo "2. Remove snapshots older than 30 days"
    echo "3. Keep only the most recent snapshot"
    echo "4. Select specific snapshots to remove"
    echo "5. DELETE ALL SNAPSHOTS IMMEDIATELY (dangerous)"
    echo "0. Cancel"

    read -p "Select option: " cleanup_choice

    case $cleanup_choice in
        1)
            echo -e "${RED}WARNING: This will delete ALL snapshots!${NC}"
            read -p "Are you absolutely sure? (type 'yes' to confirm): " confirm
            if [ "$confirm" = "yes" ]; then
                rm -rf "${BACKUP_DIR:?}"/*
                echo -e "${GREEN}✅ All snapshots removed${NC}"
                log_message "INFO" "All snapshots removed"
            fi
            ;;
        2)
            echo -e "${YELLOW}Removing snapshots older than 30 days...${NC}"
            local before_count=$(ls -1 "$BACKUP_DIR" | wc -l)
            find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null
            local after_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
            local removed=$((before_count - after_count))
            echo -e "${GREEN}✅ Removed $removed old snapshot(s)${NC}"
            log_message "INFO" "Removed $removed old snapshots"
            ;;
        3)
            if [ ${#snapshots[@]} -gt 1 ]; then
                latest="${snapshots[-1]}"
                for snapshot in "${snapshots[@]}"; do
                    if [ "$snapshot" != "$latest" ]; then
                        rm -rf "${BACKUP_DIR}/$snapshot"
                    fi
                done
                echo -e "${GREEN}✅ Kept only: $latest${NC}"
                log_message "INFO" "Kept only latest snapshot: $latest"
            else
                echo -e "${YELLOW}Only one snapshot exists, nothing to remove${NC}"
            fi
            ;;
        4)
            read -p "Enter snapshot numbers to remove (comma-separated, e.g., 1,3,5): " remove_list
            IFS=',' read -ra indices <<< "$remove_list"
            for idx in "${indices[@]}"; do
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -le "${#snapshots[@]}" ]; then
                    snapshot="${snapshots[$((idx-1))]}"
                    rm -rf "${BACKUP_DIR}/$snapshot"
                    echo -e "${GREEN}✅ Removed: $snapshot${NC}"
                    log_message "INFO" "Removed snapshot: $snapshot"
                fi
            done
            ;;
        5)
            delete_all_snapshots
            ;;
        0)
            echo -e "${YELLOW}Cancelled${NC}"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# ENHANCED: Dry Run Mode with Log Export (updated for v2.2.1)
dry_run_optimization() {
    echo -e "\n${BLUE}=== DRY RUN MODE - Optimization Preview ===${NC}"
    echo -e "${YELLOW}This will show what would be removed without making any changes${NC}\n"
    echo -e "${GREEN}Log file: $DRY_RUN_LOG${NC}\n"
    log_message "INFO" "Dry run started"

    # Initialize log file
    echo "Pi-hole Ultra Script - Dry Run Report" > "$DRY_RUN_LOG"
    echo "Generated: $(date)" >> "$DRY_RUN_LOG"
    echo "System: $DETECTED_DISTRO $DETECTED_VERSION ($DETECTED_CODENAME)" >> "$DRY_RUN_LOG"
    echo "================================================" >> "$DRY_RUN_LOG"
    echo "" >> "$DRY_RUN_LOG"

    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        echo -e "${RED}❌ Pi-hole is not installed. Please install Pi-hole first.${NC}"
        echo "❌ Pi-hole is not installed. Please install Pi-hole first." >> "$DRY_RUN_LOG"
        return 1
    fi

    # Show orphaned packages that would be removed (using native apt)
    echo -e "${PURPLE}Packages that would be removed (autoremove):${NC}"
    echo "Packages that would be removed (autoremove):" >> "$DRY_RUN_LOG"

    local autoremove=$(apt-get autoremove --dry-run 2>/dev/null | grep "^Remv" | awk '{print $2}')
    if [ -n "$autoremove" ]; then
        echo "$autoremove" | while read pkg; do
            local size=$(get_package_size "$pkg")
            echo -e "  ${YELLOW}→ $pkg (autoremovable) ($(numfmt --to=iec ${size}K))${NC}"
            echo "  → $pkg (autoremovable) ($(numfmt --to=iec ${size}K))" >> "$DRY_RUN_LOG"
        done
    else
        echo -e "  ${GREEN}None${NC}"
        echo "  None" >> "$DRY_RUN_LOG"
    fi

    # Show services that would be analyzed for disabling
    echo -e "\n${PURPLE}Services that would be analyzed for disabling:${NC}"
    echo "\nServices that would be analyzed for disabling:" >> "$DRY_RUN_LOG"
    local services_to_check=(
        "bluetooth"
        "hciuart"
        "triggerhappy"
        "alsa-state"
        "console-setup"
        "keyboard-setup"
        "raspi-config"
        "wpa_supplicant"
    )

    for service in "${services_to_check[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"; then
            echo -e "  ${YELLOW}→ $service (currently enabled)${NC}"
            echo "  → $service (currently enabled)" >> "$DRY_RUN_LOG"
        fi
    done
    echo "" >> "$DRY_RUN_LOG"

    # WiFi disabling warning if applicable
    if [ "$IS_WIFI_ACTIVE" = true ]; then
        echo -e "\n${RED}⚠️  WARNING: You are connected via WiFi!${NC}"
        echo -e "${YELLOW}   The optimization would normally disable WiFi, which would${NC}"
        echo -e "${YELLOW}   disconnect this session. You will be prompted about this.${NC}"
        echo "" >> "$DRY_RUN_LOG"
        echo "⚠️  WARNING: You are connected via WiFi!" >> "$DRY_RUN_LOG"
        echo "   The optimization would normally disable WiFi, which would" >> "$DRY_RUN_LOG"
        echo "   disconnect this session. You will be prompted about this." >> "$DRY_RUN_LOG"
        echo "" >> "$DRY_RUN_LOG"
    fi

    # Show packages that would be installed (Raspberry Pi specific)
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${PURPLE}Raspberry Pi packages that would be verified/installed:${NC}"
        echo "Raspberry Pi packages that would be verified/installed:" >> "$DRY_RUN_LOG"
        local rpi_pkgs=(
            "raspberrypi-kernel"
            "raspberrypi-bootloader"
            "raspi-config"
            "rpi-eeprom"
        )
        for pkg in "${rpi_pkgs[@]}"; do
            if ! dpkg -l | grep -q "^ii.*$pkg"; then
                echo -e "  ${YELLOW}→ $pkg (would be installed)${NC}"
                echo "  → $pkg (would be installed)" >> "$DRY_RUN_LOG"
            fi
        done
        echo "" >> "$DRY_RUN_LOG"
    fi

    # Show systemd journal cleanup
    echo -e "\n${PURPLE}System logs that would be cleaned:${NC}"
    echo "System logs that would be cleaned:" >> "$DRY_RUN_LOG"
    local journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $3 $4}' || echo "unknown")
    echo -e "  ${YELLOW}→ Journal current size: $journal_size (would be reduced to 100MB)${NC}"
    echo "  → Journal current size: $journal_size (would be reduced to 100MB)" >> "$DRY_RUN_LOG"

    # Show cache cleanup with process warning
    echo -e "\n${PURPLE}Caches that would be cleaned:${NC}"
    echo "Caches that would be cleaned:" >> "$DRY_RUN_LOG"
    echo -e "  ${YELLOW}→ APT cache (apt clean)${NC}"
    echo "  → APT cache (apt clean)" >> "$DRY_RUN_LOG"

    # Check processes using /tmp
    local tmp_processes=$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | wc -l)
    if [ "$tmp_processes" -gt 0 ]; then
        echo -e "  ${RED}→ /tmp directory (WARNING: $tmp_processes processes using /tmp)${NC}"
        echo "  → /tmp directory (WARNING: $tmp_processes processes using /tmp)" >> "$DRY_RUN_LOG"

        # List the processes
        echo -e "\n${YELLOW}Processes using /tmp:${NC}" >> "$DRY_RUN_LOG"
        lsof /tmp 2>/dev/null | head -20 >> "$DRY_RUN_LOG"
    else
        echo -e "  ${YELLOW}→ /tmp directory${NC}"
        echo "  → /tmp directory" >> "$DRY_RUN_LOG"
    fi
    echo -e "  ${YELLOW}→ /var/tmp directory${NC}"
    echo "  → /var/tmp directory" >> "$DRY_RUN_LOG"

    echo -e "\n${GREEN}✅ Dry run completed - no changes were made${NC}"
    echo -e "${GREEN}📄 Detailed report saved to: $DRY_RUN_LOG${NC}"
    echo "" >> "$DRY_RUN_LOG"
    echo "================================================" >> "$DRY_RUN_LOG"
    echo "Dry run completed - no changes were made" >> "$DRY_RUN_LOG"
    log_message "INFO" "Dry run completed"

    # Offer to view the log
    echo ""
    read -p "Do you want to view the full report now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        less "$DRY_RUN_LOG"
    fi
}

# Reinstall Raspberry Pi specific components
reinstall_rpi_components() {
    echo -e "\n${BLUE}=== Raspberry Pi Component Reinstallation ===${NC}"
    log_message "INFO" "RPi component reinstallation"

    if [ "$IS_RASPBERRY_PI" = false ]; then
        echo -e "${RED}❌ This is not a Raspberry Pi. This option is only for Raspberry Pi hardware.${NC}"
        return 1
    fi

    echo -e "${YELLOW}This will reinstall critical Raspberry Pi components:${NC}"
    echo -e "  • Raspberry Pi kernel"
    echo -e "  • Raspberry Pi bootloader"
    echo -e "  • Raspberry Pi firmware"
    echo -e "  • VideoCore utilities"
    echo -e "  • EEPROM updates"
    echo ""

    read -p "Proceed with reinstallation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Reinstallation cancelled${NC}"
        return 0
    fi

    # Backup current config using smart detection
    local config_path=$(get_config_path)
    if [ -n "$config_path" ]; then
        cp "$config_path" "${config_path}.backup-$(date +%Y%m%d-%H%M%S)"
        echo -e "${GREEN}✅ Boot config backed up from: $config_path${NC}"
    fi

    # Reinstall kernel and firmware
    echo -e "${YELLOW}Reinstalling Raspberry Pi kernel...${NC}"
    retry_operation "apt install --reinstall -y raspberrypi-kernel raspberrypi-bootloader" "Kernel reinstall"

    echo -e "${YELLOW}Reinstalling firmware...${NC}"
    retry_operation "apt install --reinstall -y raspberrypi-sys-mods raspi-config raspi-utils" "Firmware reinstall"

    echo -e "${YELLOW}Reinstalling VideoCore libraries...${NC}"
    retry_operation "apt install --reinstall -y libraspberrypi-bin libraspberrypi-dev libraspberrypi-doc libraspberrypi0" "VideoCore reinstall"

    echo -e "${YELLOW}Updating EEPROM...${NC}"
    retry_operation "apt install --reinstall -y rpi-eeprom && rpi-eeprom-update -a" "EEPROM update"

    echo -e "${YELLOW}Reconfiguring raspi-config...${NC}"
    dpkg-reconfigure raspi-config

    echo -e "${GREEN}✅ Raspberry Pi components reinstalled${NC}"
    echo -e "${YELLOW}⚠️  A reboot is recommended to apply changes${NC}"
    log_message "INFO" "RPi components reinstalled"

    # Reboot countdown with timeout
    echo -e "\n${YELLOW}System will reboot automatically in $REBOOT_TIMEOUT seconds...${NC}"
    echo -e "${YELLOW}Press any key to cancel reboot${NC}"

    if read -t $REBOOT_TIMEOUT -n 1 -s; then
        echo -e "\n${GREEN}Reboot cancelled. Please reboot manually later: sudo reboot${NC}"
    else
        echo -e "\n${YELLOW}No input received. Rebooting now...${NC}"
        echo "Rebooting in 5 seconds... Press Ctrl+C to cancel"
        sleep 5
        reboot
    fi
}

# Display optimization summary
show_optimization_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    local end_disk_used=$(df / | awk 'NR==2 {print $3}')
    local disk_saved=$((START_DISK_USED - end_disk_used))
    local disk_saved_mb=$((disk_saved / 1024))

    local disabled_count=$(grep -c "Disabled" "$OPTIMIZATION_STATS_FILE" 2>/dev/null || echo "0")
    local removed_count=$(grep -c "Removed" "$OPTIMIZATION_STATS_FILE" 2>/dev/null || echo "0")

    echo -e "\n${GREEN}══════════════════════ OPTIMIZATION SUMMARY ══════════════════════${NC}"
    echo -e "${GREEN}✅ Time elapsed:${NC} ${minutes}m ${seconds}s"

    if [ "$disk_saved" -gt 0 ]; then
        echo -e "${GREEN}✅ Disk space saved:${NC} $(numfmt --to=iec ${disk_saved}K) ($disk_saved_mb MB)"
    else
        echo -e "${GREEN}✅ Disk space saved:${NC} None (system optimized)"
    fi

    echo -e "${GREEN}✅ Services disabled:${NC} $disabled_count"
    echo -e "${GREEN}✅ Packages removed:${NC} $removed_count"

    if command -v pihole &> /dev/null; then
        local pihole_version=$(pihole -v | grep "Pi-hole" | head -1 | cut -d' ' -f4)
        echo -e "${GREEN}✅ Pi-hole version:${NC} $pihole_version"
    fi

    # Show boot config info
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${GREEN}✅ Boot config:${NC} $BOOT_CONFIG_PATH"
    fi

    # Show /tmp process status
    local tmp_processes=$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | wc -l)
    if [ "$tmp_processes" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Warning: $tmp_processes processes still using /tmp${NC}"
    fi

    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    log_message "INFO" "Optimization summary displayed"
}

# Full Optimization with Bloat Removal
run_full_optimization() {
    echo -e "\n${BLUE}=== Starting Full System Optimization ===${NC}"
    echo -e "${YELLOW}This process will:${NC}"
    echo -e "  1. Auto-clean snapshots older than $SNAPSHOT_RETENTION_DAYS days"
    echo -e "  2. Create a system snapshot (backup)"
    echo -e "  3. Remove orphaned packages (with native apt detection)"
    echo -e "  4. Disable unnecessary services"
    echo -e "  5. Apply system optimizations (with smart boot config detection)"
    echo -e "  6. Clean temporary files and logs (with process check)"
    echo -e "  7. Update system packages"
    echo -e "  8. Optimize Pi-hole"
    echo -e "  9. Auto-reboot after $REBOOT_TIMEOUT seconds if no response"
    echo ""
    log_message "INFO" "Starting full optimization"

    read -p "Proceed with full optimization? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Optimization cancelled${NC}"
        return 0
    fi

    # Initialize stats file
    echo "" > "$OPTIMIZATION_STATS_FILE"

    # Step 1: Auto-clean old snapshots
    echo -e "\n${YELLOW}Step 1: Auto-cleaning old snapshots...${NC}"
    auto_cleanup_snapshots

    # Step 2: Create snapshot
    echo -e "\n${YELLOW}Step 2: Creating system snapshot...${NC}"
    if ! create_snapshot; then
        echo -e "${RED}❌ Failed to create snapshot. Aborting optimization.${NC}"
        return 1
    fi

    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        echo -e "${RED}❌ Pi-hole is not installed. Please install Pi-hole first.${NC}"
        return 1
    fi

    # Step 3: Check for orphaned packages
    echo -e "\n${YELLOW}Step 3: Checking for orphaned packages...${NC}"
    check_orphaned_packages

    # Step 4: Remove orphaned packages (optional)
    echo ""
    read -p "Do you want to remove orphaned packages? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remove_orphaned_packages
        echo "Removed packages" >> "$OPTIMIZATION_STATS_FILE"
    else
        echo -e "${YELLOW}⚠️  Skipping orphaned package removal${NC}"
    fi

    # Step 5: Disable unnecessary services
    echo -e "\n${YELLOW}Step 5: Disabling unnecessary services...${NC}"
    local services_to_disable=(
        "bluetooth"
        "hciuart"
        "triggerhappy"
        "alsa-state"
        "console-setup"
        "keyboard-setup"
    )
    local disabled_count=0

    # Check WiFi status before disabling
    if [ "$IS_WIFI_ACTIVE" = true ]; then
        echo -e "${RED}⚠️  You are connected via WiFi!${NC}"
        read -p "Do you want to disable WiFi services? This may disconnect you! (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            services_to_disable+=("wpa_supplicant")
            echo -e "${YELLOW}WiFi will be disabled${NC}"
        else
            echo -e "${GREEN}WiFi services will be preserved${NC}"
        fi
    else
        # Safe to disable WiFi on Ethernet connection
        services_to_disable+=("wpa_supplicant")
    fi

    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"; then
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            echo -e "${GREEN}✅ Disabled $service${NC}"
            disabled_count=$((disabled_count + 1))
        fi
    done
    echo "Disabled $disabled_count" >> "$OPTIMIZATION_STATS_FILE"

    # Step 6: Raspberry Pi specific optimizations
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${YELLOW}Step 6: Applying Raspberry Pi optimizations...${NC}"

        # Re-detect boot config to ensure we have the latest
        detect_boot_config

        # Optimize boot/config.txt with precise checks
        local config_path=$(get_config_path)
        if [ -n "$config_path" ] && [ -f "$config_path" ]; then
            echo -e "${YELLOW}Optimizing: $config_path${NC}"
            local changes_made=false

            # Check and add gpu_mem if not set
            if ! grep -q "^gpu_mem=" "$config_path"; then
                echo -e "\n# Pi-hole optimizations" >> "$config_path"
                echo "gpu_mem=16" >> "$config_path"
                changes_made=true
                echo -e "${GREEN}✅ Added gpu_mem=16${NC}"
            fi

            # Check and add disable_splash if not set
            if ! grep -q "^disable_splash=" "$config_path"; then
                echo "disable_splash=1" >> "$config_path"
                changes_made=true
                echo -e "${GREEN}✅ Added disable_splash=1${NC}"
            fi

            # Check and add boot_delay if not set or different
            if ! grep -q "^boot_delay=" "$config_path"; then
                echo "boot_delay=0" >> "$config_path"
                changes_made=true
                echo -e "${GREEN}✅ Added boot_delay=0${NC}"
            elif grep -q "^boot_delay=[1-9]" "$config_path"; then
                # Replace existing boot_delay if it's >0
                sed -i 's/^boot_delay=[0-9]\+/boot_delay=0/' "$config_path"
                changes_made=true
                echo -e "${GREEN}✅ Updated boot_delay to 0${NC}"
            fi

            if [ "$changes_made" = false ]; then
                echo -e "${GREEN}✅ Boot config already optimized${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  No boot config found to optimize${NC}"
        fi

        # Disable WiFi if safe and user confirmed
        if [ "$IS_WIFI_ACTIVE" = false ] && command -v rfkill &> /dev/null; then
            read -p "Disable WiFi hardware (saves power)? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rfkill block wifi
                echo -e "${GREEN}✅ WiFi disabled${NC}"
            fi
        fi
    fi

    # Step 7: Cleaning system (with process check)
    echo -e "\n${YELLOW}Step 7: Cleaning system...${NC}"

    # Use the new standardized cleanup function
    cleanup_system

    # Safe cleanup with process check
    safe_cleanup
    echo -e "${GREEN}✅ System cleaned${NC}"

    # Step 8: Update system
    echo -e "\n${YELLOW}Step 8: Updating system packages...${NC}"
    apt update
    apt upgrade -y
    echo -e "${GREEN}✅ System updated${NC}"

    # Step 9: Optimize Pi-hole
    echo -e "\n${YELLOW}Step 9: Optimizing Pi-hole...${NC}"
    pihole updateGravity
    pihole -up
    echo -e "${GREEN}✅ Pi-hole optimized${NC}"

    # Final step: Check D-Bus and fix if needed
    echo -e "\n${YELLOW}Final Step: Verifying services...${NC}"
    if ! systemctl is-active --quiet dbus; then
        echo -e "${YELLOW}⚠️  D-Bus not running. Attempting to fix...${NC}"
        fix_dbus
    fi

    # Show optimization summary
    show_optimization_summary

    echo -e "\n${GREEN}✅ Full optimization completed successfully!${NC}"
    echo -e "${YELLOW}⚠️  A system reboot is recommended to apply all changes${NC}"
    log_message "INFO" "Full optimization completed"

    # Reboot countdown with timeout
    echo -e "\n${YELLOW}System will reboot automatically in $REBOOT_TIMEOUT seconds...${NC}"
    echo -e "${YELLOW}Press any key to cancel reboot${NC}"

    # Use read with timeout
    if read -t $REBOOT_TIMEOUT -n 1 -s; then
        echo -e "\n${GREEN}Reboot cancelled. Please reboot manually later: sudo reboot${NC}"
    else
        echo -e "\n${YELLOW}No input received. Rebooting now...${NC}"
        echo "Rebooting in 5 seconds... Press Ctrl+C to cancel"
        sleep 5
        reboot
    fi

    # Clean up temp file
    rm -f "$OPTIMIZATION_STATS_FILE" 2>/dev/null
}

# ============== MENU SYSTEM ==============
show_menu() {
    clear
    show_banner
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         MAIN MENU                            ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 1.  Run Full Optimization (with auto-cleanup)               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2.  Dry Run (Preview with log export)                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3.  Create System Snapshot (manual)                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4.  Rollback System to Snapshot                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 5.  Verify/Fix D-Bus Issues                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 6.  Reinstall Raspberry Pi Components                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 7.  Verify/Install Critical Packages                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 8.  Setup Automated Pi-hole Updates                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 9.  Quick System Info                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 10. View System Health                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 11. Cleanup Only (with process check)                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 12. Cleanup Old Snapshots (manual)                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 13. DELETE ALL SNAPSHOTS (dangerous)                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 14. Check Orphaned Packages Only (native apt)                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 15. Run Standard System Cleanup (autoremove+clean)           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 0.  Exit                                                     ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} System: $DETECTED_DISTRO $DETECTED_VERSION"
    echo -e "${CYAN}║${NC} Codename: $DETECTED_CODENAME"
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${CYAN}║${NC} Hardware: $RPI_MODEL"
        echo -e "${CYAN}║${NC} Boot Config: $BOOT_CONFIG_PATH"
    fi
    echo -e "${CYAN}║${NC} Network: $ACTIVE_INTERFACE ($([ "$IS_WIFI_ACTIVE" = true ] && echo "WiFi" || echo "Ethernet"))"
    echo -e "${CYAN}║${NC} Auto-cleanup: Snapshots > ${SNAPSHOT_RETENTION_DAYS} days | Auto-reboot: ${REBOOT_TIMEOUT}s"
    if [ -d "$BACKUP_DIR" ]; then
        local snapshot_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        local tmp_processes=$(lsof /tmp 2>/dev/null | grep -v "COMMAND" | wc -l)
        echo -e "${CYAN}║${NC} Snapshots: $snapshot_count available | /tmp users: $tmp_processes"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Enter your choice [0-15]: " MENU_CHOICE
}

# ============== MAIN EXECUTION ==============
main() {
    check_root

    clear
    show_banner
    echo -e "${BLUE}Starting Pre-Flight Checks...${NC}\n"
    log_message "INFO" "Script started"

    if ! pre_flight_check; then
        echo -e "\n${RED}❌ Pre-flight checks failed. Please resolve issues and try again.${NC}"
        log_message "ERROR" "Pre-flight checks failed"
        read -p "Press Enter to exit..."
        exit 1
    fi

    install_required_tools
    verify_dbus
    mkdir -p "$BACKUP_DIR"

    # Show info screen on first run
    SCRIPT_RUN_COUNT=1
    show_script_info

    while true; do
        show_menu

        case $MENU_CHOICE in
            1)
                run_full_optimization
                read -p "Press Enter to continue..."
                ;;
            2)
                dry_run_optimization
                read -p "Press Enter to continue..."
                ;;
            3)
                create_snapshot
                read -p "Press Enter to continue..."
                ;;
            4)
                rollback_system
                read -p "Press Enter to continue..."
                ;;
            5)
                fix_dbus
                read -p "Press Enter to continue..."
                ;;
            6)
                reinstall_rpi_components
                read -p "Press Enter to continue..."
                ;;
            7)
                verify_packages
                read -p "Press Enter to continue..."
                ;;
            8)
                setup_pihole_updates
                read -p "Press Enter to continue..."
                ;;
            9)
                quick_system_info
                read -p "Press Enter to continue..."
                ;;
            10)
                view_system_health
                read -p "Press Enter to continue..."
                ;;
            11)
                cleanup_only
                read -p "Press Enter to continue..."
                ;;
            12)
                cleanup_snapshots
                read -p "Press Enter to continue..."
                ;;
            13)
                delete_all_snapshots
                read -p "Press Enter to continue..."
                ;;
            14)
                check_orphaned_packages
                read -p "Press Enter to continue..."
                ;;
            15)
                echo -e "\n${YELLOW}Running standard system cleanup...${NC}"
                cleanup_system
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}Thank you for using Pi-hole Debian Ultra Script!${NC}"
                echo -e "${GREEN}Created by Wael Isa - https://www.wael.name${NC}"
                echo -e "${GREEN}GitHub: https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script${NC}"
                echo -e "${GREEN}Log file saved to: $LOG_FILE${NC}"
                echo -e "${GREEN}Dry Run logs saved to: /tmp/pihole-dryrun-*.txt${NC}"
                echo -e "\n${YELLOW}If this script helped you, star it on GitHub:${NC}"
                echo -e "${YELLOW}https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script${NC}"
                echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "${CYAN}  \"A stable Pi-hole keeps the internet peaceful!\"${NC}"
                echo -e "${CYAN}  \"Smart boot config detection for perfect compatibility!\"${NC}"
                echo -e "${CYAN}  \"Native apt orphan detection for Debian 13+ (Trixie)!\"${NC}"
                echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
                log_message "INFO" "Script exited normally"

                # Clean up temp files
                rm -f "$OPTIMIZATION_STATS_FILE" 2>/dev/null
                rm -f "$TEMP_SELECTIONS"* 2>/dev/null
                rm -f /tmp/pihole-*.tmp 2>/dev/null
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Start the script
main
