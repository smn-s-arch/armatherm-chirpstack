#!/bin/bash
set -euo pipefail

# --- Global Variables & Arrays ---
declare -A pre_installed
declare -a packages=("mosquitto" "mosquitto-clients" "redis-server" "redis-tools" "postgresql" "apt-transport-https" "dirmngr" "chirpstack-gateway-bridge" "chirpstack" "chirpstack-rest-api")
CONFIG_DEST="/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml"
INFO_FILE="chirpstack_install_info.txt"
# For rollback tracking:
declare -a installed_by_script=()

# --- Functions ---

# Check if a package is installed
check_installed() {
    dpkg -s "$1" &>/dev/null && return 0 || return 1
}

# Record the state of packages before running the script
record_initial_state() {
    for pkg in "${packages[@]}"; do
        if check_installed "$pkg"; then
            pre_installed["$pkg"]=1
        else
            pre_installed["$pkg"]=0
        fi
    done
}

# Rollback function to revert changes made by this script
rollback() {
    echo "Rolling back changes..."
    # Remove packages that were installed by this script (i.e. were not installed at start)
    for pkg in "${packages[@]}"; do
        if [ "${pre_installed[$pkg]}" -eq 0 ]; then
            echo "Removing package: $pkg"
            sudo apt-get remove -y "$pkg"
        fi
    done
    # Restore the original gateway bridge config if backup exists; otherwise remove the file
    if [ -f "${CONFIG_DEST}.bak" ]; then
        echo "Restoring previous configuration for chirpstack-gateway-bridge"
        sudo mv "${CONFIG_DEST}.bak" "$CONFIG_DEST"
    else
        sudo rm -f "$CONFIG_DEST"
    fi
    # Drop the chirpstack database and role if created
    echo "Dropping chirpstack database and role..."
    sudo -u postgres psql <<EOF
DROP DATABASE IF EXISTS chirpstack;
DROP ROLE IF EXISTS chirpstack;
EOF
    echo "Rollback complete."
    exit 1
}

# Ask the user if they wish to continue on error or abort and rollback
ask_continue() {
    read -rp "A step failed. Do you want to continue (c) or abort and rollback (a)? [c/a]: " choice
    if [ "$choice" == "a" ]; then
        rollback
    fi
}

# --- Main Script Execution ---

echo "Recording initial package state..."
record_initial_state

# Step 1: Ask user for ChirpStack DB credentials
read -rp "Enter ChirpStack DB username: " CHIRPSTACK_USER
read -rs -rp "Enter ChirpStack DB password: " CHIRPSTACK_PASSWORD
echo ""
echo "Credentials received."

# Step 2: Install requirements packages
echo "Updating package cache..."
if ! sudo apt-get update; then
    echo "apt-get update failed."
    ask_continue
fi

echo "Installing basic requirements: mosquitto, mosquitto-clients, redis-server, redis-tools, postgresql..."
if ! sudo apt-get install -y mosquitto mosquitto-clients redis-server redis-tools postgresql; then
    echo "Failed to install basic requirements."
    ask_continue
fi

# Record packages that we just installed
for pkg in mosquitto mosquitto-clients redis-server redis-tools postgresql; do
    if [ "${pre_installed[$pkg]}" -eq 0 ]; then
        installed_by_script+=("$pkg")
    fi
done

# Step 3: Check and install apt-transport-https and dirmngr if not present
echo "Checking and installing apt-transport-https and dirmngr..."
if ! sudo apt-get install -y apt-transport-https dirmngr; then
    echo "Installation of apt-transport-https/dirmngr failed."
    ask_continue
fi
for pkg in apt-transport-https dirmngr; do
    if [ "${pre_installed[$pkg]}" -eq 0 ]; then
        installed_by_script+=("$pkg")
    fi
done

# Step 4: Setup ChirpStack repository key and add repository list
echo "Adding ChirpStack repository key..."
if ! sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1CE2AFD36DBCCA00; then
    echo "Failed to add ChirpStack key."
    ask_continue
fi

echo "Adding ChirpStack repository to apt sources..."
if ! sudo sh -c 'echo "deb https://artifacts.chirpstack.io/packages/4.x/deb stable main" > /etc/apt/sources.list.d/chirpstack.list'; then
    echo "Failed to add ChirpStack repository."
    ask_continue
fi

# Step 5: Update package cache again
echo "Updating package cache..."
if ! sudo apt-get update; then
    echo "apt-get update failed."
    ask_continue
fi

# Step 6: Install chirpstack-gateway-bridge
echo "Installing chirpstack-gateway-bridge..."
if ! sudo apt-get install -y chirpstack-gateway-bridge; then
    echo "Installation of chirpstack-gateway-bridge failed."
    ask_continue
fi
if [ "${pre_installed["chirpstack-gateway-bridge"]}" -eq 0 ]; then
    installed_by_script+=("chirpstack-gateway-bridge")
fi

# Step 7: Copy gateway bridge configuration file
DEFAULT_CONFIG="./config/chirpstack-gateway-bridge-armatherm.toml"
if [ ! -f "$DEFAULT_CONFIG" ]; then
    read -rp "Default config file '$DEFAULT_CONFIG' not found. Please enter an alternative file path: " alt_config
    CONFIG_FILE="$alt_config"
else
    CONFIG_FILE="$DEFAULT_CONFIG"
fi

# Backup existing configuration if it exists
if [ -f "$CONFIG_DEST" ]; then
    echo "Backing up existing configuration file."
    sudo cp "$CONFIG_DEST" "${CONFIG_DEST}.bak"
fi
echo "Copying configuration file from '$CONFIG_FILE' to '$CONFIG_DEST'"
if ! sudo cp "$CONFIG_FILE" "$CONFIG_DEST"; then
    echo "Copying configuration file failed."
    ask_continue
fi

# Step 8: Start chirpstack-gateway-bridge service
echo "Starting chirpstack-gateway-bridge service..."
if ! sudo systemctl start chirpstack-gateway-bridge; then
    echo "Failed to start chirpstack-gateway-bridge."
    ask_continue
fi

# Step 9: Enable chirpstack-gateway-bridge service on boot
echo "Enabling chirpstack-gateway-bridge to start on boot..."
if ! sudo systemctl enable chirpstack-gateway-bridge; then
    echo "Failed to enable chirpstack-gateway-bridge on boot."
    ask_continue
fi

# Step 10: Create ChirpStack Database and role
echo "Creating ChirpStack database and role..."
if ! sudo -u postgres psql <<EOF
CREATE ROLE '${CHIRPSTACK_USER}' WITH LOGIN PASSWORD '${CHIRPSTACK_PASSWORD}';
CREATE DATABASE chirpstack OWNER '${CHIRPSTACK_USER}';
\c chirpstack
CREATE EXTENSION pg_trgm;
EOF
then
    echo "Database setup failed."
    ask_continue
fi

# Step 10b: Update /etc/chirpstack/chirpstack.toml with ChirpStack DB credentials
echo "Updating ChirpStack configuration with DB credentials..."
if sudo sed -i "s|^dsn = \"postgres://.*@localhost/chirpstack?sslmode=disable\"|dsn = \"postgres://${CHIRPSTACK_USER}:${CHIRPSTACK_PASSWORD}@localhost/chirpstack?sslmode=disable\"|g" /etc/chirpstack/chirpstack.toml; then
    echo "ChirpStack configuration updated successfully."
else
    echo "Failed to update ChirpStack configuration file."
    ask_continue
fi

# Step 11: Install ChirpStack
echo "Installing ChirpStack..."
if ! sudo apt-get install -y chirpstack; then
    echo "Installation of ChirpStack failed."
    ask_continue
fi
if [ "${pre_installed["chirpstack"]}" -eq 0 ]; then
    installed_by_script+=("chirpstack")
fi

# Step 11a: Start ChirpStack service
echo "Starting ChirpStack service..."
if ! sudo systemctl start chirpstack; then
    echo "Failed to start ChirpStack service."
    ask_continue
fi

# Step 11b: Enable ChirpStack service on boot
echo "Enabling ChirpStack service to start on boot..."
if ! sudo systemctl enable chirpstack; then
    echo "Failed to enable ChirpStack on boot."
    ask_continue
fi

# Step 12: Install ChirpStack REST API
echo "Installing ChirpStack REST API..."
if ! sudo apt-get install -y chirpstack-rest-api; then
    echo "Installation of ChirpStack REST API failed."
    ask_continue
fi
if [ "${pre_installed["chirpstack-rest-api"]}" -eq 0 ]; then
    installed_by_script+=("chirpstack-rest-api")
fi

# Step 13: Detect host IP automatically
HOST_IP=$(hostname -I | awk '{print $1}')
CHIRPSTACK_PORT="8080"       # Adjust this if your ChirpStack server uses a different port.
CHIRPSTACK_REST_API_PORT="8090"

# Write installation information to a text file
echo "Writing installation information to $INFO_FILE..."
{
  echo "ChirpStack DB Username: $CHIRPSTACK_USER"
  echo "ChirpStack DB Password: $CHIRPSTACK_PASSWORD"
  echo "ChirpStack Address: ${HOST_IP}:${CHIRPSTACK_PORT}"
  echo "ChirpStack REST API: ${CHIRPSTACK_REST_API}"
} > "$INFO_FILE"

# Step 14: Final checks
echo "Performing final checks..."
if ! systemctl is-active --quiet chirpstack-gateway-bridge; then
    echo "Error: chirpstack-gateway-bridge service is not running correctly."
    ask_continue
fi

echo "ChirpStack installation is complete and all steps were successful."
echo "Installation details saved in '$INFO_FILE'."

exit 0