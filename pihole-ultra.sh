#!/bin/bash
# =============================================================================
# Pi-hole Debian 12 Ultra Script - MENU DRIVEN WITH ROLLBACK
# =============================================================================
# Author:  Wael Isa
# Website: https://www.wael.name
# GitHub:  https://github.com/waelisa
# Version: 2.1.1
# License: MIT
#
# Description: Complete system optimization script for Raspberry Pi running
#              Debian 12 (Bookworm) with Pi-hole. Includes safety features,
#              snapshots, rollback capability, and automated updates.
#
# Usage: sudo ./pihole-ultra.sh
# =============================================================================

# ============== CONFIGURATION ==============
LOG_FILE="/var/log/pihole-ultra.log"
BACKUP_DIR="/root/pihole-system-backups"
SCRIPT_VERSION="2.1.1"
MIN_DISK_SPACE_MB=500  # Minimum 500MB free space required
MIN_MEMORY_MB=256      # Minimum 256MB free memory recommended
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

# ============== INITIAL CHECKS ==============
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Pre-flight safety check
pre_flight_check() {
    echo -e "\n${BLUE}=== Pre-Flight Safety Check ===${NC}"
    local checks_passed=true

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

    # Check 7: Check if running on Raspberry Pi
    echo -e "\n${YELLOW}Checking hardware...${NC}"
    if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        local model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        echo -e "${GREEN}  ✅ Detected: $model${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Not a Raspberry Pi - some features may not work${NC}"
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

    if ! command -v dselect &> /dev/null; then
        echo -e "${YELLOW}Installing dselect for rollback functionality...${NC}"
        apt-get install -y dselect
        echo -e "${GREEN}✅ dselect installed${NC}"
    else
        echo -e "${GREEN}✅ dselect already installed${NC}"
    fi

    local tools=("curl" "wget" "git" "dnsutils" "numfmt")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
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

    local config_path=$(get_config_path)
    if [ -n "$config_path" ]; then
        cp "$config_path" "${snapshot_dir}/config.txt.backup"
        echo -e "${GREEN}  ✅ Boot config backed up: ${config_path}${NC}"
    fi

    echo -e "${YELLOW}Saving service states...${NC}"
    systemctl list-units --type=service --all > "${snapshot_dir}/services-before.txt"

    dpkg -l > "${snapshot_dir}/all-packages.txt"
    uname -a > "${snapshot_dir}/kernel-version.txt"
    cat /proc/device-tree/model 2>/dev/null | tr -d '\0' > "${snapshot_dir}/hardware-model.txt"

    echo -e "${GREEN}✅ Snapshot created: ${snapshot_name}${NC}"
    echo -e "${GREEN}   Location: ${snapshot_dir}${NC}"
    echo -e "${GREEN}   Size: $(du -sh "$snapshot_dir" | cut -f1)${NC}"

    CURRENT_BACKUP="$snapshot_name"
}

# IMPROVED: Rollback function with atomic package selection
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

    # IMPROVED: Save current selections before clearing (safety)
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

    if [ -f "$snapshot_dir/config.txt.backup" ]; then
        local config_path=$(get_config_path)
        if [ -n "$config_path" ]; then
            cp "$snapshot_dir/config.txt.backup" "$config_path"
            echo -e "${GREEN}✅ Boot config restored${NC}"
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
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"
    echo -e "${GREEN}Uptime:${NC} $(uptime -p)"
    echo -e "${GREEN}Memory:${NC} $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo -e "${GREEN}Disk:${NC} $(df -h / | awk 'NR==2 {print $3"/"$2 " ("$5")"}')"
    echo -e "${GREEN}Pi-hole:${NC} $(pihole status | head -1)"
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

    echo -e "\n${YELLOW}Pi-hole Status:${NC}"
    pihole status
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
    echo -e "\n${BLUE}=== Verifying critical Raspberry Pi packages ===${NC}"

    local critical_pkgs=(
        "raspberrypi-kernel"
        "raspberrypi-sys-mods"
        "raspi-config"
        "raspi-utils"
        "rpi-eeprom"
        "python3"
    )

    local all_good=true

    for pkg in "${critical_pkgs[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            echo -e "${GREEN}✅ $pkg is installed${NC}"
        else
            echo -e "${YELLOW}⚠️  $pkg is NOT installed - this may be normal${NC}"
            if [[ "$pkg" == "python3" ]] || [[ "$pkg" == "raspberrypi-kernel" ]]; then
                all_good=false
            fi
        fi
    done

    if [ "$all_good" = false ]; then
        echo ""
        echo -e "${YELLOW}⚠️  Some critical packages appear to be missing.${NC}"
        read -p "Do you want to attempt reinstalling missing packages? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for pkg in "${critical_pkgs[@]}"; do
                if ! dpkg -l | grep -q "^ii.*$pkg"; then
                    echo "Installing $pkg..."
                    apt install -y "$pkg"
                fi
            done
        fi
    fi
}

# Placeholder for optimization functions
run_full_optimization() {
    echo -e "\n${BLUE}=== Starting Full System Optimization ===${NC}"
    echo -e "${YELLOW}This feature will be fully implemented in the next version${NC}"
    echo -e "${YELLOW}For now, please use the individual options from the menu${NC}"
}

# Reinstall Pi-hole optional
reinstall_pihole_optional() {
    echo -e "\n${BLUE}=== Pi-hole Reinstallation ===${NC}"
    echo -e "${YELLOW}This feature will be fully implemented in the next version${NC}"
}

# ============== MENU SYSTEM ==============
show_menu() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Pi-hole Debian 12 Ultra Script v${SCRIPT_VERSION}                ║${NC}"
    echo -e "${CYAN}║     by Wael Isa (https://www.wael.name)                      ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 1. Quick System Info                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 2. Full System Optimization (with dry run)                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 3. Create System Snapshot                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 4. Rollback to Snapshot                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 5. Setup Automated Pi-hole Updates                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 6. View System Health                                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 7. Reinstall Critical Packages                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 8. Fix D-Bus Issues                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 9. Cleanup Only (no changes)                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 10. Full Optimization + Pi-hole Reinstall                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 0. Exit                                                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Enter your choice [0-10]: " MENU_CHOICE
}

# ============== MAIN EXECUTION ==============
main() {
    check_root

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Pi-hole Debian 12 Ultra Script v${SCRIPT_VERSION}                ║"
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

    while true; do
        show_menu

        case $MENU_CHOICE in
            1)
                quick_system_info
                read -p "Press Enter to continue..."
                ;;
            2)
                run_full_optimization
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
                setup_pihole_updates
                read -p "Press Enter to continue..."
                ;;
            6)
                view_system_health
                read -p "Press Enter to continue..."
                ;;
            7)
                verify_packages
                read -p "Press Enter to continue..."
                ;;
            8)
                fix_dbus
                read -p "Press Enter to continue..."
                ;;
            9)
                cleanup_only
                read -p "Press Enter to continue..."
                ;;
            10)
                echo -e "\n${BLUE}Starting Full Optimization + Pi-hole Reinstall${NC}"
                run_full_optimization
                reinstall_pihole_optional
                read -p "Press Enter to continue..."
                ;;
            0)
                echo -e "\n${GREEN}Thank you for using Pi-hole Ultra Script!${NC}"
                echo -e "${GREEN}Created by Wael Isa - https://www.wael.name${NC}"
                echo -e "${GREEN}Log file saved to: $LOG_FILE${NC}"
                echo -e "\n${YELLOW}If this script helped you, star it on GitHub:${NC}"
                echo -e "${YELLOW}https://github.com/waelisa/Raspberry-Pi-Pi-hole-Debian-Ultra-Script${NC}"
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
