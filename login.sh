#!/bin/bash

# Constants
SSH_KEY_NAME="rht_classroom.rsa"
SSH_KEY_SOURCE="$HOME/Downloads/$SSH_KEY_NAME"
SSH_KEY_DEST="$HOME/.ssh/$SSH_KEY_NAME"
REQUIRED_PERMISSIONS="600"
CONFIG_DIR="$HOME/.config/role_script_ssh"
CONFIG_FILE="$CONFIG_DIR/connection.conf"
KNOWN_HOSTS_FILE="$CONFIG_DIR/temp_known_hosts"
LAB_PASSWORD="student"
SSH_CONFIG_FILE="$HOME/.ssh/config"
CURSOR_HOST_NAME="lab-workstation"

# SSH options for non-interactive connections
SSH_OPTIONS=(
    -o "StrictHostKeyChecking=no"
    -o "UserKnownHostsFile=/dev/null"
    -o "LogLevel=ERROR"
    -o "GlobalKnownHostsFile=/dev/null"
    -o "BatchMode=yes"
)

check_sshpass() {
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "sshpass is not installed. Attempting to install..."
        
        # Check package manager and install
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y sshpass
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y sshpass
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm sshpass
        else
            echo "Error: Could not install sshpass. Please install it manually."
            return 1
        fi
    fi
    return 0
}

# Helper functions
check_key_exists() {
    if [[ -f "$SSH_KEY_DEST" ]]; then
        return 0
    else
        return 1
    fi
}

check_key_permissions() {
    local perms
    perms=$(stat -c "%a" "$SSH_KEY_DEST" 2>/dev/null)
    if [[ "$perms" == "$REQUIRED_PERMISSIONS" ]]; then
        return 0
    else
        return 1
    fi
}

check_ssh_agent() {
    if ssh-add -l | grep -q "$SSH_KEY_DEST"; then
        return 0
    else
        return 1
    fi
}

store_connection_config() {
    local conn_string="$1"
    
    if ! parse_connection_string "$conn_string"; then
        return 1
    fi
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Store connection details
    cat > "$CONFIG_FILE" << EOF
JUMP_HOST=$JUMP_HOST
JUMP_PORT=$JUMP_PORT
TARGET_HOST=$TARGET_HOST
TARGET_PORT=$TARGET_PORT
EOF
    
    chmod 600 "$CONFIG_FILE"
    
    # Create empty known_hosts file if it doesn't exist
    touch "$KNOWN_HOSTS_FILE"
    chmod 600 "$KNOWN_HOSTS_FILE"
}

load_connection_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    
    # Source the config file
    source "$CONFIG_FILE"
    
    # Verify all required variables are set
    if [[ -z "$JUMP_HOST" ]] || [[ -z "$JUMP_PORT" ]] || [[ -z "$TARGET_HOST" ]] || [[ -z "$TARGET_PORT" ]]; then
        return 1
    fi
    
    return 0
}

setup_key() {
    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    
    # Check if key already exists in destination
    if [[ -f "$SSH_KEY_DEST" ]]; then
        echo "SSH key already exists at $SSH_KEY_DEST"
        chmod "$REQUIRED_PERMISSIONS" "$SSH_KEY_DEST"
    else
        # Move key if it exists in Downloads
        if [[ -f "$SSH_KEY_SOURCE" ]]; then
            mv "$SSH_KEY_SOURCE" "$SSH_KEY_DEST"
        else
            echo "Error: SSH key not found at $SSH_KEY_SOURCE"
            return 1
        fi
    fi
    
    # Set correct permissions
    chmod "$REQUIRED_PERMISSIONS" "$SSH_KEY_DEST"
    
    # Add to ssh-agent
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$SSH_KEY_DEST"
    
    echo "SSH key setup completed successfully"
    return 0
}

parse_connection_string() {
    local conn_string="$1"
    # Expected format: "cloud-user@<jump_host_ip>:<jump_host_port> student@<target_host_ip> -p <target_host_port>"
    
    if [[ "$conn_string" =~ ^([^@]+@[^:]+):([0-9]+)[[:space:]]+([^@]+@[^[:space:]]+)[[:space:]]-p[[:space:]]*([0-9]+)$ ]]; then
        JUMP_HOST="${BASH_REMATCH[1]}"
        JUMP_PORT="${BASH_REMATCH[2]}"
        TARGET_HOST="${BASH_REMATCH[3]}"
        TARGET_PORT="${BASH_REMATCH[4]}"
        return 0
    else
        echo "Error: Invalid connection string format"
        echo "Expected format: cloud-user@jump_host_ip:jump_port student@target_host_ip -p target_port"
        return 1
    fi
}

ensure_ssh_agent() {
    # Start ssh-agent if not running and set environment
    if ! pgrep -u "$USER" ssh-agent >/dev/null; then
        eval "$(ssh-agent -s)" >/dev/null
    else
        # If agent is running but environment isn't set, try to set it
        if [[ -z "$SSH_AGENT_PID" ]]; then
            SSH_AGENT_SOCK=$(find /tmp -uid $(id -u) -type s -name agent.\* 2>/dev/null | head -n 1)
            if [[ -n "$SSH_AGENT_SOCK" ]]; then
                export SSH_AUTH_SOCK="$SSH_AGENT_SOCK"
                SSH_AGENT_PID=$(ps -u "$USER" | grep ssh-agent | awk '{print $1}')
                export SSH_AGENT_PID
            else
                # If we can't find existing agent, start a new one
                eval "$(ssh-agent -s)" >/dev/null
            fi
        fi
    fi
    
    # Check if the key exists and has correct permissions
    if ! check_key_exists; then
        echo "SSH key not found at $SSH_KEY_DEST"
        return 1
    fi
    
    if ! check_key_permissions; then
        echo "Fixing SSH key permissions..."
        chmod "$REQUIRED_PERMISSIONS" "$SSH_KEY_DEST"
    fi
    
    # Add key if not already added
    if ! ssh-add -l 2>/dev/null | grep -q "$SSH_KEY_DEST"; then
        if ! ssh-add "$SSH_KEY_DEST" 2>/dev/null; then
            echo "Failed to add key to ssh-agent"
            return 1
        fi
    fi
    
    return 0
}

connect_ssh() {
    local conn_string="$1"
    
    # Ensure key exists and has correct permissions
    if ! check_key_exists; then
        echo "SSH key not found. Running setup first..."
        if ! setup_key; then
            return 1
        fi
    elif ! check_key_permissions; then
        echo "Fixing SSH key permissions..."
        chmod "$REQUIRED_PERMISSIONS" "$SSH_KEY_DEST"
    fi
    
    if [[ -n "$conn_string" ]]; then
        # If connection string provided, parse and store it
        if ! parse_connection_string "$conn_string"; then
            return 1
        fi
        store_connection_config "$conn_string"
    else
        # If no connection string provided, try to load from config
        if ! load_connection_config; then
            echo "Error: No connection string provided and no stored configuration found"
            return 1
        fi
    fi
    
    echo "Connecting to lab environment..."
    
    # Create a temporary SSH config file for this connection
    local tmp_ssh_config="$CONFIG_DIR/tmp_ssh_config"
    cat > "$tmp_ssh_config" << EOF
Host jump target
    IdentityFile $SSH_KEY_DEST
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    BatchMode yes

Host jump
    HostName $(echo "$JUMP_HOST" | cut -d@ -f2)
    User $(echo "$JUMP_HOST" | cut -d@ -f1)
    Port $JUMP_PORT

Host target
    HostName $(echo "$TARGET_HOST" | cut -d@ -f2)
    User $(echo "$TARGET_HOST" | cut -d@ -f1)
    Port $TARGET_PORT
    ProxyJump jump
EOF
    
    chmod 600 "$tmp_ssh_config"
    
    # Use the temporary config file for the connection
    ssh -F "$tmp_ssh_config" target
    
    # Clean up the temporary config file
    rm -f "$tmp_ssh_config"
}

clean_setup() {
    # Remove key from ssh-agent
    ssh-add -d "$SSH_KEY_DEST" 2>/dev/null
    
    # Remove key file
    rm -f "$SSH_KEY_DEST"

    # Clean up the configuration directory and all its contents
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
    fi
    
    echo "Cleanup completed successfully"
}

show_status() {
    echo "SSH Key Status:"
    echo "-------------"
    
    if check_key_exists; then
        echo "✓ SSH key exists at $SSH_KEY_DEST"
        if check_key_permissions; then
            echo "✓ SSH key has correct permissions ($REQUIRED_PERMISSIONS)"
        else
            echo "✗ SSH key has incorrect permissions"
        fi
    else
        echo "✗ SSH key not found at $SSH_KEY_DEST"
    fi
    
    if check_ssh_agent; then
        echo "✓ SSH key is added to ssh-agent"
    else
        echo "✗ SSH key is not added to ssh-agent"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "✓ Connection configuration exists"
        if [[ -f "$KNOWN_HOSTS_FILE" ]]; then
            local host_count=$(wc -l < "$KNOWN_HOSTS_FILE")
            echo "✓ Temporary known_hosts file exists with $host_count entries"
        fi
    else
        echo "✗ No stored connection configuration"
    fi
    
    if command -v sshpass >/dev/null 2>&1; then
        echo "✓ sshpass is installed"
    else
        echo "✗ sshpass is not installed"
    fi
}

show_help() {
    cat << EOF
Role Script SSH - Lab Environment Connection Manager
================================================

A utility for managing SSH connections to ephemeral lab virtual machines.

USAGE:
    $(basename "$0") <command> [options]

COMMANDS:
    setup [connection_string]     Set up SSH key and optionally connect
        - Moves SSH key from Downloads to ~/.ssh
        - Sets correct permissions (600)
        - Adds key to ssh-agent
        - Stores connection details if provided
        - Optionally connects immediately
    
    connect [connection_string]   Connect to the lab environment
        - Uses stored connection details if no string provided
        - Automatically handles host key verification
        - Automatically provides lab password
        - Creates new configuration if connection string provided
    
    cursor [connection_string]     Set up SSH key and optionally connect for Cursor IDE
        - Moves SSH key from Downloads to ~/.ssh
        - Sets correct permissions (600)
        - Adds key to ssh-agent
        - Stores connection details if provided
        - Optionally connects immediately
    
    clean                        Clean up all configuration
        - Removes SSH key from agent
        - Removes key file from ~/.ssh
        - Removes stored connection details
        - Removes temporary known_hosts entries
    
    status                       Show current configuration status
        - SSH key presence and permissions
        - SSH agent status
        - Connection configuration status
        - Known hosts entries count
        - sshpass availability

OPTIONS:
    --help, -h                   Show this help message

CONNECTION STRING FORMAT:
    "cloud-user@<jump_host_ip>:<jump_host_port> student@<target_host_ip> -p <target_port>"

EXAMPLES:
    # Initial setup with connection:
    $(basename "$0") setup "cloud-user@148.62.94.60:22022 student@172.25.252.1 -p 53009"

    # Connect using stored configuration:
    $(basename "$0") connect

    # Connect with new configuration:
    $(basename "$0") connect "cloud-user@148.62.94.60:22022 student@172.25.252.1 -p 53009"

    # Check current status:
    $(basename "$0") status

    # Clean up everything:
    $(basename "$0") clean

NOTES:
    - The script automatically handles:
        * SSH key setup and permissions
        * Host key verification (without prompts)
        * Password authentication (using static lab password)
        * Connection detail storage
    
    - First run may require sudo access to install sshpass
    - All configuration is stored in ~/.config/role_script_ssh/
    - Uses a separate known_hosts file to avoid conflicts
EOF
}

validate_ssh_config() {
    local jump_host="$1"
    local jump_port="$2"
    local target_host="$3"
    local target_port="$4"
    
    if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
        return 0
    fi
    
    # Check if the host is already configured
    if grep -q "^Host $CURSOR_HOST_NAME\$" "$SSH_CONFIG_FILE"; then
        local config_jump_host=$(awk -v RS='' '/^Host '"$CURSOR_HOST_NAME"'$/ {
            while(getline) {
                if ($1 == "ProxyJump") {
                    split($2, a, "[:]")
                    print a[1]
                    exit
                }
            }
        }' "$SSH_CONFIG_FILE")
        
        local config_target_host=$(awk -v RS='' '/^Host '"$CURSOR_HOST_NAME"'$/ {
            while(getline) {
                if ($1 == "HostName") {
                    print $2
                    exit
                }
            }
        }' "$SSH_CONFIG_FILE")
        
        local config_target_port=$(awk -v RS='' '/^Host '"$CURSOR_HOST_NAME"'$/ {
            while(getline) {
                if ($1 == "Port") {
                    print $2
                    exit
                }
            }
        }' "$SSH_CONFIG_FILE")
        
        # Compare with new values
        if [[ "$config_jump_host" != "$jump_host" ]] || \
           [[ "$config_target_host" != "$target_host" ]] || \
           [[ "$config_target_port" != "$target_port" ]]; then
            echo "Warning: Existing SSH config for $CURSOR_HOST_NAME has different values."
            echo "Existing configuration:"
            echo "  Jump Host: $config_jump_host"
            echo "  Target Host: $config_target_host"
            echo "  Target Port: $config_target_port"
            echo "New configuration:"
            echo "  Jump Host: $jump_host"
            echo "  Target Host: $target_host"
            echo "  Target Port: $target_port"
            echo "Updating configuration..."
            return 0
        else
            echo "Existing SSH config matches current connection details."
            return 1
        fi
    fi
    
    return 0
}

update_ssh_config() {
    local jump_user=$(echo "$JUMP_HOST" | cut -d@ -f1)
    local jump_host=$(echo "$JUMP_HOST" | cut -d@ -f2)
    local target_user=$(echo "$TARGET_HOST" | cut -d@ -f1)
    local target_host=$(echo "$TARGET_HOST" | cut -d@ -f2)
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    
    # Create or update SSH config
    if ! validate_ssh_config "$jump_host" "$JUMP_PORT" "$target_host" "$TARGET_PORT"; then
        return 0
    fi
    
    # Backup existing config if it exists
    if [[ -f "$SSH_CONFIG_FILE" ]]; then
        cp "$SSH_CONFIG_FILE" "$SSH_CONFIG_FILE.bak"
    fi
    
    # Remove existing host configuration if present
    if [[ -f "$SSH_CONFIG_FILE" ]]; then
        sed -i "/^Host $CURSOR_HOST_NAME$/,/^$/d" "$SSH_CONFIG_FILE"
    fi
    
    # Add new configuration
    cat >> "$SSH_CONFIG_FILE" << EOF

Host jump-host
    HostName $jump_host
    User $jump_user
    Port $JUMP_PORT
    IdentityFile $SSH_KEY_DEST
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null

Host $CURSOR_HOST_NAME
    HostName $target_host
    User $target_user
    Port $TARGET_PORT
    IdentityFile $SSH_KEY_DEST
    ProxyCommand ssh -W %h:%p jump-host
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    BatchMode yes

EOF
    
    chmod 600 "$SSH_CONFIG_FILE"
    echo "SSH config updated successfully."
}

setup_cursor() {
    local conn_string="$1"
    
    # Ensure key exists and has correct permissions
    if ! check_key_exists; then
        echo "SSH key not found. Running setup first..."
        if ! setup_key; then
            return 1
        fi
    elif ! check_key_permissions; then
        echo "Fixing SSH key permissions..."
        chmod "$REQUIRED_PERMISSIONS" "$SSH_KEY_DEST"
    fi
    
    if [[ -n "$conn_string" ]]; then
        # If connection string provided, parse and store it
        if ! parse_connection_string "$conn_string"; then
            return 1
        fi
        store_connection_config "$conn_string"
    else
        # If no connection string provided, try to load from config
        if ! load_connection_config; then
            echo "Error: No connection string provided and no stored configuration found"
            return 1
        fi
    fi
    
    # Update SSH config for Cursor
    update_ssh_config
    
    # Test connection using the same method as connect_ssh
    echo "Testing SSH connection..."
    if ! connect_ssh "$conn_string"; then
        echo "Error: Failed to connect to remote host. Please check your SSH configuration."
        return 1
    fi
    
    echo "SSH configuration has been set up for Cursor IDE."
    echo ""
    echo "To connect in Cursor IDE:"
    echo "1. Click the Remote SSH button in the bottom-left corner"
    echo "2. Select 'Connect to Host...'"
    echo "3. Choose '$CURSOR_HOST_NAME' from the list"
    echo ""
    echo "Or use these settings manually:"
    echo "  Host: $CURSOR_HOST_NAME"
    echo "  Username: $(echo "$TARGET_HOST" | cut -d@ -f1)"
    echo "  SSH Key: $SSH_KEY_DEST"
    echo ""
    
    # Launch Cursor IDE
    echo "Launching Cursor IDE with remote connection..."
    cursor --remote ssh-remote+$CURSOR_HOST_NAME &

    # Give instructions for manual connection if needed
    echo ""
    echo "If the automatic connection fails, you can connect manually:"
    echo "1. Click the Remote SSH button (bottom-left corner)"
}

# Main command handler
case "$1" in
    "setup")
        if [[ -z "$2" ]]; then
            setup_key
        else
            setup_key && connect_ssh "$2"
        fi
        ;;
    "connect")
        if [[ -z "$2" ]]; then
            connect_ssh
        else
            connect_ssh "$2"
        fi
        ;;
    "cursor")
        if [[ -z "$2" ]]; then
            setup_cursor
        else
            setup_cursor "$2"
        fi
        ;;
    "clean")
        clean_setup
        ;;
    "status")
        show_status
        ;;
    "--help"|"-h")
        show_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo "Run '$(basename "$0") --help' for usage information"
        exit 1
        ;;
esac