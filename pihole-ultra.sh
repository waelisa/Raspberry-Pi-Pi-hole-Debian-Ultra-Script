#!/bin/bash
# =============================================================================
# Pi-hole Debian Ultra Script - MENU DRIVEN WITH ROLLBACK
# =============================================================================
# Author:  Wael Isa
# Website: https://www.wael.name
# GitHub:  https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script
# Version: 2.1.3
# License: MIT
#
# Description: Complete system optimization script for systems running
#              Debian with Pi-hole. Includes safety features,
#              snapshots, rollback capability, and automated updates.
#              Compatible with Raspberry Pi and other Debian installations.
#
# Usage: sudo ./pihole-ultra.sh
# =============================================================================

# ============== CONFIGURATION ==============
LOG_FILE="/var/log/pihole-ultra.log"
BACKUP_DIR="/root/pihole-system-backups"
SCRIPT_VERSION="2.1.3"
MIN_DISK_SPACE_MB=500  # Minimum 500MB free space required
MIN_MEMORY_MB=256      # Minimum 256MB free memory recommended
DRY_RUN=false
exec > >(tee -a "$LOG_FILE") 2>&1

# ============== COLOR CODES FOR MENU ==============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============== GLOBAL VARIABLES ==============
CURRENT_BACKUP=""
MENU_CHOICE=""
TEMP_SELECTIONS="/tmp/dpkg-selections.$$"
DETECTED_DISTRO=""
DETECTED_VERSION=""
IS_RASPBERRY_PI=false
RPI_MODEL=""
ACTIVE_INTERFACE=""
IS_WIFI_ACTIVE=false

# ============== INITIAL CHECKS ==============
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Display script information and what it does
show_script_info() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Pi-hole Debian Ultra Script - INFORMATION          ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} This script optimizes your Debian system with Pi-hole by:    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 1. Creating system snapshots (backup) before any changes     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2. Removing unnecessary packages (orphaned)                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3. Disabling non-essential services                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4. Optimizing system for Pi-hole performance                  ${CYAN}${NC}"
    echo -e "${CYAN}║${NC} 5. Cleaning temporary files and logs                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 6. Setting up automated Pi-hole updates                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 7. Fixing common issues (D-Bus, services)                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 8. Raspberry Pi specific optimizations (if detected)          ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} SAFETY FEATURES:                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Full system snapshots before optimization                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Rollback capability to restore previous state               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Dry-run mode to preview changes without applying            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Network connectivity checks before disabling services       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} • Confirmation prompts for critical operations                ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Press Enter to continue to the main menu..."
}

# Detect active network interface
detect_active_interface() {
    echo -e "\n${BLUE}=== Detecting Active Network Connection ===${NC}"

    # Get default route interface
    ACTIVE_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -n "$ACTIVE_INTERFACE" ]; then
        echo -e "${GREEN}✅ Default route via: $ACTIVE_INTERFACE${NC}"

        # Check if it's a WiFi interface
        if [[ "$ACTIVE_INTERFACE" == wlan* ]] || [[ "$ACTIVE_INTERFACE" == wlp* ]]; then
            IS_WIFI_ACTIVE=true
            echo -e "${YELLOW}⚠️  Active connection is via WIFI ($ACTIVE_INTERFACE)${NC}"
            echo -e "${YELLOW}   Disabling WiFi would disconnect this session!${NC}"
        else
            IS_WIFI_ACTIVE=false
            echo -e "${GREEN}✅ Active connection is via Ethernet (safe to disable WiFi)${NC}"
        fi
    else
        echo -e "${RED}❌ Could not detect active network interface${NC}"
        IS_WIFI_ACTIVE=false
    fi
}

# Detect Debian version and compatibility
detect_debian_version() {
    if [ -f /etc/debian_version ]; then
        DETECTED_VERSION=$(cat /etc/debian_version)
        DETECTED_DISTRO="Debian"
        echo -e "${GREEN}✅ Detected: Debian $DETECTED_VERSION${NC}"

        # Check if it's actually Raspbian/Raspberry Pi OS (which is Debian-based)
        if grep -q "Raspbian" /etc/os-release 2>/dev/null; then
            DETECTED_DISTRO="Raspbian"
            echo -e "${GREEN}✅ Detected: Raspbian/Debian $DETECTED_VERSION${NC}"
        fi
        return 0
    elif [ -f /etc/os-release ]; then
        # Try to get from os-release
        source /etc/os-release
        if [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            DETECTED_VERSION="$VERSION_ID"
            DETECTED_DISTRO="$NAME"
            echo -e "${GREEN}✅ Detected: $NAME $VERSION_ID${NC}"
            return 0
        fi
    fi

    echo -e "${YELLOW}⚠️  Warning: This doesn't appear to be a Debian-based system${NC}"
    echo -e "${YELLOW}   Some features may not work correctly${NC}"
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
            return 0
        fi
    fi

    # Alternative detection methods
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        IS_RASPBERRY_PI=true
        RPI_MODEL="Raspberry Pi (from cpuinfo)"
        echo -e "${GREEN}✅ Raspberry Pi detected${NC}"
        return 0
    fi

    IS_RASPBERRY_PI=false
    return 1
}

# Pre-flight safety check
pre_flight_check() {
    echo -e "\n${BLUE}=== Pre-Flight Safety Check ===${NC}"
    local checks_passed=true

    # Detect system info
    detect_debian_version
    detect_raspberry_pi
    detect_active_interface

    # Check 1: Available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local available_space_mb=$((available_space / 1024))

    echo -e "${YELLOW}Checking disk space...${NC}"
    echo -e "  Available: ${available_space_mb}MB"
    echo -e "  Required: ${MIN_DISK_SPACE_MB}MB"

    if [ "$available_space_mb" -lt "$MIN_DISK_SPACE_MB" ]; then
        echo -e "${RED}  ❌ Insufficient disk space!${NC}"
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
    else
        echo -e "${GREEN}  ✅ Adequate memory${NC}"
    fi

    # Check 3: Internet connectivity
    echo -e "\n${YELLOW}Checking internet connectivity...${NC}"
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${GREEN}  ✅ Internet connected${NC}"
    else
        echo -e "${RED}  ❌ No internet connection!${NC}"
        checks_passed=false
    fi

    # Check 4: DNS resolution
    echo -e "\n${YELLOW}Checking DNS resolution...${NC}"
    if nslookup google.com &> /dev/null; then
        echo -e "${GREEN}  ✅ DNS working${NC}"
    else
        echo -e "${YELLOW}  ⚠️  DNS resolution failed (Pi-hole may not be running)${NC}"
    fi

    # Check 5: Write permission to backup directory
    echo -e "\n${YELLOW}Checking backup directory...${NC}"
    if mkdir -p "$BACKUP_DIR" && touch "$BACKUP_DIR/test.tmp" 2>/dev/null; then
        rm -f "$BACKUP_DIR/test.tmp"
        echo -e "${GREEN}  ✅ Backup directory writable${NC}"
    else
        echo -e "${RED}  ❌ Cannot write to backup directory!${NC}"
        checks_passed=false
    fi

    # Check 6: Package manager status
    echo -e "\n${YELLOW}Checking package manager...${NC}"
    if ! apt-get update -qq &> /dev/null; then
        echo -e "${RED}  ❌ Package manager update failed!${NC}"
        checks_passed=false
    else
        echo -e "${GREEN}  ✅ Package manager working${NC}"
    fi

    echo -e "\n${BLUE}=== Pre-Flight Summary ===${NC}"
    if [ "$checks_passed" = true ]; then
        echo -e "${GREEN}✅ All critical checks passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Critical checks failed. Please fix issues before proceeding.${NC}"
        return 1
    fi
}

# Install required tools
install_required_tools() {
    echo -e "\n${BLUE}=== Checking Required Tools ===${NC}"

    apt-get update -qq

    # IMPORTANT: Ensure dselect is installed for rollback functionality
    if ! command -v dselect &> /dev/null; then
        echo -e "${YELLOW}Installing dselect for rollback functionality...${NC}"
        apt-get install -y dselect
        echo -e "${GREEN}✅ dselect installed${NC}"
    else
        echo -e "${GREEN}✅ dselect already installed${NC}"
    fi

    local tools=("curl" "wget" "git" "dnsutils" "numfmt" "lsb-release" "deborphan" "rfkill" "ethtool")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null && ! dpkg -l | grep -q "ii  $tool "; then
            echo -e "${YELLOW}Installing $tool...${NC}"
            apt-get install -y "$tool"
        fi
    done
}

# Verify D-Bus is working
verify_dbus() {
    echo -e "\n${BLUE}=== Verifying D-Bus System Bus ===${NC}"

    if ! systemctl is-active --quiet dbus; then
        echo -e "${YELLOW}⚠️  D-Bus system bus not running. Attempting to start...${NC}"
        systemctl start dbus
        sleep 2

        if systemctl is-active --quiet dbus; then
            echo -e "${GREEN}✅ D-Bus started successfully${NC}"
        else
            echo -e "${RED}❌ Failed to start D-Bus. Some functions may not work.${NC}"
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

# Get config.txt path
get_config_path() {
    # Raspberry Pi paths
    if [ -f "/boot/firmware/config.txt" ]; then
        echo "/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        echo "/boot/config.txt"
    else
        echo ""
    fi
}

# Estimate backup size
estimate_backup_size() {
    echo -e "\n${BLUE}=== Estimating Backup Size ===${NC}"

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

    # Backup boot configs if they exist
    local config_path=$(get_config_path)
    if [ -n "$config_path" ]; then
        cp "$config_path" "${snapshot_dir}/config.txt.backup"
        echo -e "${GREEN}  ✅ Boot config backed up: ${config_path}${NC}"

        # Also backup boot directory if it exists
        if [ -d "/boot/firmware" ]; then
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

    echo -e "${GREEN}✅ Snapshot created: ${snapshot_name}${NC}"
    echo -e "${GREEN}   Location: ${snapshot_dir}${NC}"
    echo -e "${GREEN}   Size: $(du -sh "$snapshot_dir" | cut -f1)${NC}"

    CURRENT_BACKUP="$snapshot_name"
}

# Rollback function
rollback_system() {
    echo -e "\n${PURPLE}=== System Rollback ===${NC}"

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ No backup directory found at $BACKUP_DIR${NC}"
        return 1
    fi

    local snapshots=($(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r))

    if [ ${#snapshots[@]} -eq 0 ]; then
        echo -e "${RED}❌ No snapshots found to rollback to${NC}"
        return 1
    fi

    echo -e "${YELLOW}Available snapshots (most recent first):${NC}"
    for i in "${!snapshots[@]}"; do
        local size=$(du -sh "${BACKUP_DIR}/${snapshots[$i]}" 2>/dev/null | cut -f1)
        echo "$((i+1)). ${snapshots[$i]} (${size})"
    done

    echo ""
    read -p "Select snapshot to rollback to (or 0 to cancel): " snapshot_choice

    if [ "$snapshot_choice" = "0" ]; then
        echo -e "${YELLOW}Rollback cancelled${NC}"
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
        # Clear selections and restore in one logical block
        if dpkg --clear-selections && dpkg --set-selections < "$snapshot_dir/package-list.txt"; then
            echo -e "${GREEN}✅ Package selections restored successfully${NC}"

            echo -e "${BLUE}Applying package changes (this may take a while)...${NC}"
            if apt-get dselect-upgrade -y; then
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

    # Restore boot config from multiple possible backup locations
    if [ -f "$snapshot_dir/config.txt.backup" ]; then
        local config_path=$(get_config_path)
        if [ -n "$config_path" ]; then
            cp "$snapshot_dir/config.txt.backup" "$config_path"
            echo -e "${GREEN}✅ Boot config restored${NC}"
        fi
    fi

    # Restore full firmware backup if it exists
    if [ -d "$snapshot_dir/firmware-backup" ]; then
        if [ -d "/boot/firmware" ]; then
            cp -r "$snapshot_dir/firmware-backup"/* /boot/firmware/ 2>/dev/null
            echo -e "${GREEN}✅ Firmware directory restored${NC}"
        fi
    fi

    # Clean up temp file
    rm -f "${TEMP_SELECTIONS}.current" 2>/dev/null

    echo -e "${GREEN}✅ Rollback completed${NC}"
    echo -e "${YELLOW}⚠️  A system reboot is REQUIRED to complete rollback${NC}"

    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Rebooting in 10 seconds... Press Ctrl+C to cancel"
        sleep 10
        reboot
    else
        echo -e "${YELLOW}Please reboot manually later: sudo reboot${NC}"
    fi
}

# Setup automated Pi-hole updates
setup_pihole_updates() {
    echo -e "\n${BLUE}=== Pi-hole Automated Updates Setup ===${NC}"

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

    crontab -l | grep "pihole updateGravity"
}

# Quick system info
quick_system_info() {
    echo -e "\n${BLUE}=== Quick System Information ===${NC}"
    echo -e "${GREEN}Hostname:${NC} $(hostname)"
    echo -e "${GREEN}OS:${NC} $DETECTED_DISTRO $DETECTED_VERSION"
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"
    echo -e "${GREEN}Uptime:${NC} $(uptime -p)"
    echo -e "${GREEN}Memory:${NC} $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo -e "${GREEN}Disk:${NC} $(df -h / | awk 'NR==2 {print $3"/"$2 " ("$5")"}')"
    echo -e "${GREEN}Active Network:${NC} $ACTIVE_INTERFACE ($([ "$IS_WIFI_ACTIVE" = true ] && echo "WiFi" || echo "Ethernet"))"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${GREEN}Hardware:${NC} $RPI_MODEL"
        # Get CPU temperature if available
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            CPU_TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
            echo -e "${GREEN}CPU Temp:${NC} ${CPU_TEMP}°C"
        fi
    fi

    if command -v pihole &> /dev/null; then
        echo -e "${GREEN}Pi-hole:${NC} $(pihole status | head -1)"
    else
        echo -e "${YELLOW}Pi-hole:${NC} Not installed"
    fi

    echo -e "${GREEN}D-Bus:${NC} $(systemctl is-active dbus)"
    echo -e "${GREEN}Failed Services:${NC} $(systemctl --failed | grep -c "loaded failed" || echo "0")"
}

# View system health
view_system_health() {
    echo -e "\n${BLUE}=== System Health Report ===${NC}"

    echo -e "\n${YELLOW}D-Bus Status:${NC}"
    systemctl status dbus --no-pager | head -3

    echo -e "\n${YELLOW}Failed Services:${NC}"
    systemctl --failed --no-pager || echo "None"

    echo -e "\n${YELLOW}Recent System Errors:${NC}"
    journalctl -p 3 -b --no-pager | tail -5

    echo -e "\n${YELLOW}Disk Health:${NC}"
    df -h | grep -E "^/dev|Filesystem"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${YELLOW}Raspberry Pi Specific:${NC}"
        vcgencmd measure_temp 2>/dev/null && vcgencmd get_throttled 2>/dev/null
    fi

    if command -v pihole &> /dev/null; then
        echo -e "\n${YELLOW}Pi-hole Status:${NC}"
        pihole status
    fi
}

# Fix D-Bus
fix_dbus() {
    echo -e "\n${BLUE}=== D-Bus Repair Utility ===${NC}"

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
    else
        echo -e "${RED}❌ D-Bus still not running. Trying emergency fix...${NC}"
        dbus-daemon --system --fork
        sleep 2
        systemctl start dbus
    fi

    systemctl status dbus --no-pager | head -3
}

# Cleanup only
cleanup_only() {
    echo -e "\n${BLUE}=== Safe Cleanup Mode ===${NC}"
    echo -e "${YELLOW}This will only clean temporary files and logs${NC}"

    read -p "Proceed with safe cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    apt autoremove --purge -y
    apt autoclean -y
    apt clean
    journalctl --vacuum-time=7d
    rm -rf /tmp/*
    rm -rf /var/tmp/*

    echo -e "${GREEN}✅ Safe cleanup completed${NC}"
    echo -e "Disk space now: $(df -h / | awk 'NR==2 {print $4}') free"
}

# Verify packages
verify_packages() {
    echo -e "\n${BLUE}=== Verifying critical packages ===${NC}"

    local critical_pkgs=(
        "ca-certificates"
        "curl"
        "wget"
        "gnupg"
        "apt-utils"
        "systemd"
        "dbus"
        "python3"
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
                apt install -y "$pkg"
            done
            echo -e "${GREEN}✅ Missing packages installed${NC}"
        fi
    else
        echo -e "${GREEN}✅ All critical packages are installed${NC}"
    fi
}

# NEW: Clean up old snapshots to save space
cleanup_snapshots() {
    echo -e "\n${BLUE}=== Snapshot Cleanup ===${NC}"

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
        echo "$((i+1)). ${snapshots[$i]} (${size})"
    done

    echo ""
    echo "Options:"
    echo "1. Remove all snapshots"
    echo "2. Remove snapshots older than 30 days"
    echo "3. Keep only the most recent snapshot"
    echo "4. Select specific snapshots to remove"
    echo "0. Cancel"

    read -p "Select option: " cleanup_choice

    case $cleanup_choice in
        1)
            echo -e "${RED}WARNING: This will delete ALL snapshots!${NC}"
            read -p "Are you absolutely sure? (type 'yes' to confirm): " confirm
            if [ "$confirm" = "yes" ]; then
                rm -rf "${BACKUP_DIR:?}"/*
                echo -e "${GREEN}✅ All snapshots removed${NC}"
            fi
            ;;
        2)
            echo -e "${YELLOW}Removing snapshots older than 30 days...${NC}"
            find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null
            echo -e "${GREEN}✅ Old snapshots removed${NC}"
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
                fi
            done
            ;;
        0)
            echo -e "${YELLOW}Cancelled${NC}"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# Dry Run Mode - Show what would be removed without actually removing
dry_run_optimization() {
    echo -e "\n${BLUE}=== DRY RUN MODE - Optimization Preview ===${NC}"
    echo -e "${YELLOW}This will show what would be removed without making any changes${NC}\n"

    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        echo -e "${RED}❌ Pi-hole is not installed. Please install Pi-hole first.${NC}"
        return 1
    fi

    # Show orphaned packages that would be removed
    echo -e "${PURPLE}Packages that would be removed (orphaned):${NC}"
    local orphans=$(deborphan)
    local orphan_count=0
    if [ -n "$orphans" ]; then
        echo "$orphans" | while read pkg; do
            echo -e "  ${YELLOW}→ $pkg${NC}"
            orphan_count=$((orphan_count + 1))
        done
    else
        echo -e "  ${GREEN}None found${NC}"
    fi
    echo -e "${GREEN}Total orphaned packages: $orphan_count${NC}\n"

    # Show services that would be disabled (non-essential)
    echo -e "${PURPLE}Services that would be analyzed for disabling:${NC}"
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
        fi
    done

    # WiFi disabling warning if applicable
    if [ "$IS_WIFI_ACTIVE" = true ]; then
        echo -e "\n${RED}⚠️  WARNING: You are connected via WiFi!${NC}"
        echo -e "${YELLOW}   The optimization would normally disable WiFi, which would${NC}"
        echo -e "${YELLOW}   disconnect this session. You will be prompted about this.${NC}"
    fi

    # Show packages that would be installed (Raspberry Pi specific)
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${PURPLE}Raspberry Pi packages that would be verified/installed:${NC}"
        local rpi_pkgs=(
            "raspberrypi-kernel"
            "raspberrypi-bootloader"
            "raspi-config"
            "rpi-eeprom"
        )
        for pkg in "${rpi_pkgs[@]}"; do
            if ! dpkg -l | grep -q "^ii.*$pkg"; then
                echo -e "  ${YELLOW}→ $pkg (would be installed)${NC}"
            fi
        done
    fi

    # Show systemd journal cleanup
    echo -e "\n${PURPLE}System logs that would be cleaned:${NC}"
    local journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $3 $4}' || echo "unknown")
    echo -e "  ${YELLOW}→ Journal current size: $journal_size (would be reduced to 100MB)${NC}"

    # Show cache cleanup
    echo -e "\n${PURPLE}Caches that would be cleaned:${NC}"
    echo -e "  ${YELLOW}→ APT cache (apt clean)${NC}"
    echo -e "  ${YELLOW}→ Temporary files (/tmp, /var/tmp)${NC}"

    echo -e "\n${GREEN}✅ Dry run completed - no changes were made${NC}"
}

# Reinstall Raspberry Pi specific components
reinstall_rpi_components() {
    echo -e "\n${BLUE}=== Raspberry Pi Component Reinstallation ===${NC}"

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

    # Backup current config
    local config_path=$(get_config_path)
    if [ -n "$config_path" ]; then
        cp "$config_path" "${config_path}.backup-$(date +%Y%m%d-%H%M%S)"
        echo -e "${GREEN}✅ Boot config backed up${NC}"
    fi

    # Reinstall kernel and firmware
    echo -e "${YELLOW}Reinstalling Raspberry Pi kernel...${NC}"
    apt install --reinstall -y raspberrypi-kernel raspberrypi-bootloader

    echo -e "${YELLOW}Reinstalling firmware...${NC}"
    apt install --reinstall -y raspberrypi-sys-mods raspi-config raspi-utils

    echo -e "${YELLOW}Reinstalling VideoCore libraries...${NC}"
    apt install --reinstall -y libraspberrypi-bin libraspberrypi-dev libraspberrypi-doc libraspberrypi0

    echo -e "${YELLOW}Updating EEPROM...${NC}"
    apt install --reinstall -y rpi-eeprom
    rpi-eeprom-update -a

    echo -e "${YELLOW}Reconfiguring raspi-config...${NC}"
    dpkg-reconfigure raspi-config

    echo -e "${GREEN}✅ Raspberry Pi components reinstalled${NC}"
    echo -e "${YELLOW}⚠️  A reboot is recommended to apply changes${NC}"

    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
}

# Full Optimization with Bloat Removal
run_full_optimization() {
    echo -e "\n${BLUE}=== Starting Full System Optimization ===${NC}"
    echo -e "${YELLOW}This process will:${NC}"
    echo -e "  1. Create a system snapshot (backup)"
    echo -e "  2. Remove orphaned packages (with confirmation)"
    echo -e "  3. Disable unnecessary services"
    echo -e "  4. Apply system optimizations"
    echo -e "  5. Clean temporary files and logs"
    echo -e "  6. Update system packages"
    echo -e "  7. Optimize Pi-hole"
    echo ""

    read -p "Proceed with full optimization? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Optimization cancelled${NC}"
        return 0
    fi

    # Step 1: Create snapshot
    echo -e "\n${YELLOW}Step 1: Creating system snapshot...${NC}"
    if ! create_snapshot; then
        echo -e "${RED}❌ Failed to create snapshot. Aborting optimization.${NC}"
        return 1
    fi

    # Check if Pi-hole is installed
    if ! command -v pihole &> /dev/null; then
        echo -e "${RED}❌ Pi-hole is not installed. Please install Pi-hole first.${NC}"
        return 1
    fi

    # Step 2: Remove orphaned packages with confirmation
    echo -e "\n${YELLOW}Step 2: Checking for orphaned packages...${NC}"
    local orphans=$(deborphan)
    if [ -n "$orphans" ]; then
        echo -e "${PURPLE}The following orphaned packages were found:${NC}"
        echo "$orphans" | while read pkg; do
            echo -e "  ${YELLOW}→ $pkg${NC}"
        done
        echo ""
        read -p "Remove these orphaned packages? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$orphans" | xargs apt-get remove --purge -y
            echo -e "${GREEN}✅ Orphaned packages removed${NC}"
        else
            echo -e "${YELLOW}⚠️  Skipping orphaned package removal${NC}"
        fi
    else
        echo -e "${GREEN}✅ No orphaned packages found${NC}"
    fi

    # Step 3: Disable unnecessary services
    echo -e "\n${YELLOW}Step 3: Disabling unnecessary services...${NC}"
    local services_to_disable=(
        "bluetooth"
        "hciuart"
        "triggerhappy"
        "alsa-state"
        "console-setup"
        "keyboard-setup"
    )

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
        fi
    done

    # Step 4: Raspberry Pi specific optimizations
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "\n${YELLOW}Step 4: Applying Raspberry Pi optimizations...${NC}"

        # Optimize boot/config.txt with precise checks
        local config_path=$(get_config_path)
        if [ -n "$config_path" ]; then
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

    # Step 5: Cleaning system
    echo -e "\n${YELLOW}Step 5: Cleaning system...${NC}"
    apt autoremove --purge -y
    apt autoclean -y
    apt clean
    journalctl --vacuum-size=100M
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    echo -e "${GREEN}✅ System cleaned${NC}"

    # Step 6: Update system
    echo -e "\n${YELLOW}Step 6: Updating system packages...${NC}"
    apt update
    apt upgrade -y
    echo -e "${GREEN}✅ System updated${NC}"

    # Step 7: Optimize Pi-hole
    echo -e "\n${YELLOW}Step 7: Optimizing Pi-hole...${NC}"
    pihole updateGravity
    pihole -up
    echo -e "${GREEN}✅ Pi-hole optimized${NC}"

    # Final step: Check D-Bus and fix if needed
    echo -e "\n${YELLOW}Final Step: Verifying services...${NC}"
    if ! systemctl is-active --quiet dbus; then
        echo -e "${YELLOW}⚠️  D-Bus not running. Attempting to fix...${NC}"
        fix_dbus
    fi

    echo -e "\n${GREEN}✅ Full optimization completed!${NC}"
    echo -e "${YELLOW}⚠️  A system reboot is recommended to apply all changes${NC}"

    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Rebooting in 10 seconds... Press Ctrl+C to cancel"
        sleep 10
        reboot
    else
        echo -e "${YELLOW}Please reboot manually later: sudo reboot${NC}"
    fi
}

# ============== MENU SYSTEM ==============
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Pi-hole Debian Ultra Script v${SCRIPT_VERSION}                    ║${NC}"
    echo -e "${CYAN}║     by Wael Isa (https://www.wael.name)                      ║${NC}"
    echo -e "${CYAN}║     GitHub: https://github.com/waelisa                       ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 1.  Run Full Optimization (with snapshot)                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2.  Dry Run (Preview changes without applying)               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3.  Create System Snapshot (manual)                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4.  Rollback System to Snapshot                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 5.  Verify/Fix D-Bus Issues                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 6.  Reinstall Raspberry Pi Components                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 7.  Verify/Install Critical Packages                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 8.  Setup Automated Pi-hole Updates                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 9.  Quick System Info                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 10. View System Health                                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 11. Cleanup Only (safe mode)                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 12. Cleanup Old Snapshots (save space)                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 0.  Exit                                                     ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} System: $DETECTED_DISTRO $DETECTED_VERSION"
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${CYAN}║${NC} Hardware: $RPI_MODEL"
    fi
    echo -e "${CYAN}║${NC} Network: $ACTIVE_INTERFACE ($([ "$IS_WIFI_ACTIVE" = true ] && echo "WiFi" || echo "Ethernet"))"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Enter your choice [0-12]: " MENU_CHOICE
}

# ============== MAIN EXECUTION ==============
main() {
    check_root

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Pi-hole Debian Ultra Script v${SCRIPT_VERSION}                    ║"
    echo "║     by Wael Isa (https://www.wael.name)                      ║"
    echo "║     GitHub: https://github.com/waelisa                       ║"
    echo "║           Starting Pre-Flight Checks...                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if ! pre_flight_check; then
        echo -e "\n${RED}❌ Pre-flight checks failed. Please resolve issues and try again.${NC}"
        read -p "Press Enter to exit..."
        exit 1
    fi

    install_required_tools
    verify_dbus
    mkdir -p "$BACKUP_DIR"

    # Show info screen on first run
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
            0)
                echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}Thank you for using Pi-hole Debian Ultra Script!${NC}"
                echo -e "${GREEN}Created by Wael Isa - https://www.wael.name${NC}"
                echo -e "${GREEN}GitHub: https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script${NC}"
                echo -e "${GREEN}Log file saved to: $LOG_FILE${NC}"
                echo -e "\n${YELLOW}If this script helped you, star it on GitHub:${NC}"
                echo -e "${YELLOW}https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script${NC}"
                echo -e "\n${CYAN}Remember: A stable Pi-hole keeps the internet peaceful!${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
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
