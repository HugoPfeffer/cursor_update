#!/bin/bash

# Script to automate the SSH setup for the RHT lab environment.
# Usage: 
#   source ./login.sh [command] [args]
#   ./login.sh [command] [args]
#   or set RHT_* environment variables

# --- Check if script is being sourced ---
# This needs to be at the top to ensure correct detection
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0

# --- Status Tracking ---
STATUS_FILE="/tmp/rht_login_${USER}_status.json"

# Function to initialize or reset status file
init_status() {
    cat > "$STATUS_FILE" << EOF
{
    "last_run": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "sourced": $SOURCED,
    "steps": {
        "config_checked": false,
        "key_setup": false,
        "alias_created": false,
        "ssh_config_updated": false
    },
    "connection": {
        "cloud_jump": "",
        "student_target": "",
        "student_port": "",
        "key_path": ""
    }
}
EOF
    chmod 600 "$STATUS_FILE"
}

# Function to update status
update_status() {
    local key="$1"
    local value="$2"
    local temp_file="/tmp/rht_login_${USER}_status_temp.json"
    
    if [ ! -f "$STATUS_FILE" ]; then
        init_status
    fi
    
    # Use jq if available for proper JSON handling
    if command -v jq >/dev/null 2>&1; then
        jq --arg key "$key" --arg val "$value" \
           '.steps[$key] = ($val == "true")' "$STATUS_FILE" > "$temp_file" 2>/dev/null && \
        mv "$temp_file" "$STATUS_FILE" || {
            # Fallback to sed if jq fails
            sed -i "s/\"$key\": [^,}]*/\"$key\": $value/" "$STATUS_FILE"
        }
    else
        # Fallback to sed for basic string replacement
        sed -i "s/\"$key\": [^,}]*/\"$key\": $value/" "$STATUS_FILE"
    fi
}

# Function to update connection details in status
update_connection_status() {
    local temp_file="/tmp/rht_login_${USER}_status_temp.json"
    
    if [ ! -f "$STATUS_FILE" ]; then
        init_status
    fi
    
    if command -v jq >/dev/null 2>&1; then
        jq --arg cj "$CLOUD_JUMP" \
           --arg st "$STUDENT_TARGET" \
           --arg sp "$STUDENT_PORT" \
           --arg kp "${FOUND_KEY_PATH:-}" \
           '.connection.cloud_jump = $cj | 
            .connection.student_target = $st |
            .connection.student_port = $sp |
            .connection.key_path = $kp' \
           "$STATUS_FILE" > "$temp_file" && \
        mv "$temp_file" "$STATUS_FILE"
    else
        # Fallback without jq
        sed -i "s/\"cloud_jump\": \"[^\"]*\"/\"cloud_jump\": \"$CLOUD_JUMP\"/" "$STATUS_FILE"
        sed -i "s/\"student_target\": \"[^\"]*\"/\"student_target\": \"$STUDENT_TARGET\"/" "$STATUS_FILE"
        sed -i "s/\"student_port\": \"[^\"]*\"/\"student_port\": \"$STUDENT_PORT\"/" "$STATUS_FILE"
        sed -i "s/\"key_path\": \"[^\"]*\"/\"key_path\": \"${FOUND_KEY_PATH:-}\"/" "$STATUS_FILE"
    fi
}

# Function to read status
get_status() {
    local key="$1"
    if [ ! -f "$STATUS_FILE" ]; then
        echo "false"
        return
    fi
    
    if command -v jq >/dev/null 2>&1; then
        jq -r ".steps.$key" "$STATUS_FILE"
    else
        grep "\"$key\":" "$STATUS_FILE" | sed 's/.*: \([^,}]*\).*/\1/'
    fi
}

# Function to clean up on script exit
cleanup() {
    # Clean up status file
    [ -f "$STATUS_FILE" ] && rm -f "$STATUS_FILE"
    
    # If script is being uninstalled or fails, restore original known_hosts
    if [ "${1:-}" = "uninstall" ] || [ "${1:-}" = "error" ]; then
        manage_known_hosts "restore"
    fi
}

# Register cleanup handlers
trap 'cleanup error' ERR
trap cleanup EXIT

# --- Help and Usage Information ---
show_help() {
    cat << EOF
login.sh - Automated SSH Setup for RHT Lab Environment

USAGE:
    source ./login.sh [COMMAND] [OPTIONS] [ARGS]
    ./login.sh [COMMAND] [OPTIONS] [ARGS]

COMMANDS:
    setup       Full setup: find SSH key, move it, set permissions, create alias
    start       Create alias and store environments (assumes key already setup)
    connect     Return the connection command/alias (assumes everything setup)
    cursor      Open Cursor IDE connected to the lab environment
    status      Show current setup status and connection details
    
    If no command is provided, 'setup' is used by default.

OPTIONS:
    --help, -h    Show this help message

CONNECTION ARGUMENTS:
    cloud_jump     - Cloud jump host in format user@ip:port (e.g., cloud-user@example.com:22022)
    student_target - Student target in format user@ip (e.g., student@172.25.252.1)
    -p port        - Port flag (-p) followed by the port number for the student connection

ENVIRONMENT VARIABLES:
    You can set these environment variables before sourcing to avoid interactive prompts:
    
    RHT_CLOUD_JUMP      - Cloud jump host in format user@ip:port
    RHT_STUDENT_TARGET  - Student target in format user@ip
    RHT_STUDENT_PORT    - Port for the student connection (numeric only, without -p)

PRIORITY:
    The script determines connection details in this order:
    1. Command-line arguments (if provided)
    2. Environment variables (if set)
    3. Interactive prompts (if neither arguments nor environment variables are available)

ALIAS PROVIDED:
    When sourced, this script provides the following shell alias:
    
    rh-connect  - Connect to the lab environment using the configured settings

EXAMPLES:
    # Source the script with setup command
    source ./login.sh setup cloud-user@example.com:22022 student@172.25.252.1 -p 53009
    
    # Only create the alias with pre-configured environments
    source ./login.sh start
    
    # Just connect (assuming everything is setup)
    source ./login.sh connect
    
    # Open Cursor IDE connected to the lab environment
    ./login.sh cursor
    
    # Execute the script with setup (won't provide the rh-connect alias)
    ./login.sh setup cloud-user@example.com:22022 student@172.25.252.1 -p 53009
    
    # Source the script with default setup and follow interactive prompts
    source ./login.sh
    
    # After sourcing, connect to the lab
    rh-connect
    
    # Add to PATH for easier access
    # You can then use it like:
    login.sh setup
    login.sh start
    login.sh connect
    login.sh cursor
EOF
}

# --- Configuration Variables (No Defaults) ---
CLOUD_JUMP=""
STUDENT_TARGET=""
STUDENT_PORT=""

KEY_NAME="rht_classroom.rsa"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
DOWNLOADS_DIR="$HOME/Downloads"
KEY_PATH_IN_SSH="$SSH_DIR/$KEY_NAME"
KEY_PATH_IN_DOWNLOADS="$DOWNLOADS_DIR/$KEY_NAME"
FOUND_KEY_PATH="" # Variable to store the path if found outside Downloads/.ssh
ENV_FILE="$HOME/.rht_env"

# Known hosts management
KNOWN_HOSTS="$SSH_DIR/known_hosts"
KNOWN_HOSTS_MANAGED="$SSH_DIR/.rht_managed_hosts"
KNOWN_HOSTS_BACKUP="$SSH_DIR/.known_hosts.backup"

# Function to manage known_hosts entries
manage_known_hosts() {
    local action="$1"  # 'clean' or 'add'
    local cloud_host="$2"
    local student_host="$3"
    
    # Ensure SSH directory exists
    mkdir -p "$SSH_DIR" 2>/dev/null
    
    case "$action" in
        clean)
            # Create backup of current known_hosts if it exists
            if [ -f "$KNOWN_HOSTS" ]; then
                cp "$KNOWN_HOSTS" "$KNOWN_HOSTS_BACKUP" 2>/dev/null
            fi
            
            # If we have managed entries, remove them from known_hosts
            if [ -f "$KNOWN_HOSTS_MANAGED" ]; then
                echo "Cleaning up previously managed known_hosts entries..."
                while IFS= read -r host; do
                    ssh-keygen -R "$host" 2>/dev/null || true
                done < "$KNOWN_HOSTS_MANAGED"
                # Clear the managed hosts file
                > "$KNOWN_HOSTS_MANAGED"
            fi
            ;;
            
        add)
            # Add hosts to our managed list
            if [ -n "$cloud_host" ]; then
                echo "$cloud_host" >> "$KNOWN_HOSTS_MANAGED"
            fi
            if [ -n "$student_host" ]; then
                echo "$student_host" >> "$KNOWN_HOSTS_MANAGED"
            fi
            
            # Sort and remove duplicates from managed hosts
            if [ -f "$KNOWN_HOSTS_MANAGED" ]; then
                sort -u "$KNOWN_HOSTS_MANAGED" > "${KNOWN_HOSTS_MANAGED}.tmp"
                mv "${KNOWN_HOSTS_MANAGED}.tmp" "$KNOWN_HOSTS_MANAGED"
            fi
            ;;
            
        restore)
            # Restore original known_hosts from backup if it exists
            if [ -f "$KNOWN_HOSTS_BACKUP" ]; then
                echo "Restoring known_hosts from backup..."
                mv "$KNOWN_HOSTS_BACKUP" "$KNOWN_HOSTS"
            fi
            ;;
            
        *)
            error_message "Invalid action for manage_known_hosts: $action"
            return 1
            ;;
    esac
    
    return 0
}

# Function to extract hosts from connection details
get_connection_hosts() {
    # Extract hosts from current connection details
    local cloud_host=""
    local student_host=""
    
    if [ -n "$CLOUD_JUMP" ]; then
        cloud_host=$(echo "$CLOUD_JUMP" | cut -d@ -f2 | cut -d: -f1)
    fi
    if [ -n "$STUDENT_TARGET" ]; then
        student_host=$(echo "$STUDENT_TARGET" | cut -d@ -f2)
    fi
    
    echo "$cloud_host $student_host"
}

# --- Helper Functions ---
error_message() {
    echo "Error: $1" >&2
    if [ "$SOURCED" -eq 1 ]; then
        return 1
    else
        exit 1 # Exit if run directly
    fi
}

# Function to check and set configuration variables
check_config() {
    # Initialize status tracking
    init_status
    
    # Load saved environment if available
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null
    fi
    
    # Skip first argument if it's a command
    local args=("$@")
    local start_index=0
    
    if [[ "$1" == "setup" || "$1" == "start" || "$1" == "connect" || "$1" == "cursor" ]]; then
        start_index=1
    fi
    
    # Parse command-line arguments in SSH format
    # We expect: [cloud_jump] [student_target] [-p port]
    local arg_count=$#
    local arg_index=$((start_index + 1))
    
    # First argument should be cloud jump host
    if [ -n "${args[$start_index]}" ]; then
        CLOUD_JUMP="${args[$start_index]}"
        arg_index=$((arg_index + 1))
    fi
    
    # Second argument should be student target
    if [ $arg_count -ge $((start_index + 2)) ] && [ -n "${args[$((start_index + 1))]}" ]; then
        STUDENT_TARGET="${args[$((start_index + 1))]}"
        arg_index=$((arg_index + 1))
    fi
    
    # Check for -p flag followed by port
    if [ $arg_count -ge $((start_index + 4)) ] && [ "${args[$((start_index + 2))]}" = "-p" ] && [ -n "${args[$((start_index + 3))]}" ]; then
        STUDENT_PORT="${args[$((start_index + 3))]}"
    elif [ $arg_count -ge $((start_index + 3)) ] && [ "${args[$((start_index + 2))]}" = "-p" ]; then
        # Handle case where -p is present but port is missing
        error_message "Port number must follow the -p flag."
        return 1
    fi
    
    # If still empty, check environment variables
    if [ -z "$CLOUD_JUMP" ]; then
        CLOUD_JUMP=${RHT_CLOUD_JUMP}
    fi
    
    if [ -z "$STUDENT_TARGET" ]; then
        STUDENT_TARGET=${RHT_STUDENT_TARGET}
    fi
    
    if [ -z "$STUDENT_PORT" ]; then
        STUDENT_PORT=${RHT_STUDENT_PORT}
    fi

    # If still empty after checking args and env vars, prompt interactively
    if [ -z "$CLOUD_JUMP" ]; then
        read -p "Enter Cloud Jump Host (user@ip:port): " CLOUD_JUMP
        if [ -z "$CLOUD_JUMP" ]; then error_message "Cloud Jump Host is required."; return 1; fi
    fi
    
    if [ -z "$STUDENT_TARGET" ]; then
        read -p "Enter Student Target (user@ip): " STUDENT_TARGET
        if [ -z "$STUDENT_TARGET" ]; then error_message "Student Target is required."; return 1; fi
    fi
    
    if [ -z "$STUDENT_PORT" ]; then
        read -p "Enter Student Port: " STUDENT_PORT
        if [ -z "$STUDENT_PORT" ]; then error_message "Student Port is required."; return 1; fi
    fi
    
    # Export them so the alias can use them
    export CLOUD_JUMP STUDENT_TARGET STUDENT_PORT
    
    # Store in persistent environment file
    mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null
    echo "export RHT_CLOUD_JUMP=\"$CLOUD_JUMP\"" > "$ENV_FILE"
    echo "export RHT_STUDENT_TARGET=\"$STUDENT_TARGET\"" >> "$ENV_FILE"
    echo "export RHT_STUDENT_PORT=\"$STUDENT_PORT\"" >> "$ENV_FILE"
    chmod 600 "$ENV_FILE" 2>/dev/null
    
    echo "Connection details saved to $ENV_FILE"
    
    # Update status after successful configuration
    update_status "config_checked" "true"
    update_connection_status
    
    return 0
}

# Function to setup SSH key
setup_ssh_key() {
    # Check if key is already setup
    if [ "$(get_status "key_setup")" = "true" ] && [ -n "$FOUND_KEY_PATH" ] && [ -f "$FOUND_KEY_PATH" ]; then
        echo "SSH key already setup at: $FOUND_KEY_PATH"
        return 0
    fi
    
    # Ensure the .ssh directory exists with correct permissions
    mkdir -p "$SSH_DIR" 2>/dev/null || {
        error_message "Could not create $SSH_DIR directory. Please check permissions."
        return 1
    }
    chmod 700 "$SSH_DIR" 2>/dev/null
    
    # Clean up known_hosts entries
    read -r cloud_host student_host <<< "$(get_connection_hosts)"
    manage_known_hosts "clean" "$cloud_host" "$student_host"
    
    # Always start by checking if the key exists in ~/.ssh and removing it
    if [ -f "$KEY_PATH_IN_SSH" ]; then
        echo "Existing key '$KEY_NAME' found in $SSH_DIR. Removing to use the latest key."
        rm -f "$KEY_PATH_IN_SSH" 2>/dev/null || {
            error_message "Failed to remove existing key from $SSH_DIR."
            return 1
        }
    fi
    
    # Now look for the key in Downloads
    if [ -f "$KEY_PATH_IN_DOWNLOADS" ]; then
        echo "Moving key from $DOWNLOADS_DIR to $SSH_DIR..."
        mv "$KEY_PATH_IN_DOWNLOADS" "$SSH_DIR/" 2>/dev/null || {
            error_message "Failed to move key from $DOWNLOADS_DIR to $SSH_DIR."
            return 1
        }
        FOUND_KEY_PATH="$KEY_PATH_IN_SSH"
    else
        # If not in Downloads, search the home directory (excluding .ssh)
        echo "Searching for key '$KEY_NAME' in home directory..."
        TEMP_FOUND_PATH=$(find "$HOME" -path "$SSH_DIR" -prune -o -name "$KEY_NAME" -type f -print -quit 2>/dev/null)
        
        if [ -n "$TEMP_FOUND_PATH" ]; then
            echo "Moving key from $(dirname "$TEMP_FOUND_PATH") to $SSH_DIR..."
            mv "$TEMP_FOUND_PATH" "$SSH_DIR/" 2>/dev/null || {
                error_message "Failed to move key from $(dirname "$TEMP_FOUND_PATH") to $SSH_DIR."
                return 1
            }
            FOUND_KEY_PATH="$KEY_PATH_IN_SSH"
        else
            echo "Key '$KEY_NAME' not found. Please ensure you have downloaded the key and try again."
            echo "Expected locations:"
            echo "  - $DOWNLOADS_DIR/$KEY_NAME"
            echo "  - Anywhere in your home directory"
            return 1
        fi
    fi
    
    # Set permissions for the key
    chmod 0600 "$FOUND_KEY_PATH" 2>/dev/null || {
        error_message "Failed to set permissions (chmod 0600) on $FOUND_KEY_PATH."
        return 1
    }
    
    # Verify key permissions
    KEY_PERMS=$(stat -c "%a" "$FOUND_KEY_PATH" 2>/dev/null)
    if [ "$KEY_PERMS" != "600" ]; then
        error_message "Failed to set correct permissions on key. Current: $KEY_PERMS, Expected: 600"
        return 1
    fi
    
    # Export FOUND_KEY_PATH so the alias can use it
    export FOUND_KEY_PATH
    
    # Update environment file with key path
    if [ -f "$ENV_FILE" ]; then
        # Remove any existing FOUND_KEY_PATH line
        grep -v "FOUND_KEY_PATH" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null
        mv "${ENV_FILE}.tmp" "$ENV_FILE" 2>/dev/null
    fi
    echo "export FOUND_KEY_PATH=\"$FOUND_KEY_PATH\"" >> "$ENV_FILE"
    
    # Kill any existing ssh-agent
    if [ -n "$SSH_AGENT_PID" ]; then
        echo "Stopping existing ssh-agent..."
        kill "$SSH_AGENT_PID" 2>/dev/null || true
    fi
    
    # Start fresh ssh-agent
    echo "Starting new ssh-agent session..."
    eval "$(ssh-agent)" || {
        echo "Warning: Failed to start ssh-agent. SSH key won't be cached."
        return 0
    }
    
    # Add the key to ssh-agent with verbose output
    echo "Adding key to ssh-agent: $FOUND_KEY_PATH"
    if ! ssh-add -v "$FOUND_KEY_PATH" 2>&1; then
        echo "Warning: Failed to add key to ssh-agent. You may be prompted for passphrase when connecting."
    fi
    
    # Verify the key was added
    echo "Verifying key in ssh-agent..."
    if ssh-add -l | grep -q "$FOUND_KEY_PATH"; then
        echo "Successfully verified key in ssh-agent"
    fi
    
    # Update status after successful key setup
    update_status "key_setup" "true"
    update_connection_status
    
    return 0
}

# Function to update SSH config file
update_ssh_config() {
    # Check if config is already updated
    if [ "$(get_status "ssh_config_updated")" = "true" ]; then
        echo "SSH config already up to date"
        return 0
    fi
    
    # Ensure SSH directory exists with correct permissions
    mkdir -p "$SSH_DIR" 2>/dev/null
    chmod 700 "$SSH_DIR" 2>/dev/null

    # Create config file if it doesn't exist
    touch "$SSH_CONFIG" 2>/dev/null
    chmod 600 "$SSH_CONFIG" 2>/dev/null

    # Extract host and port from cloud jump
    local cloud_user_host=${CLOUD_JUMP%:*}
    local cloud_port=${CLOUD_JUMP##*:}

    # Extract user and host from student target
    local student_user=${STUDENT_TARGET%@*}
    local student_host=${STUDENT_TARGET#*@}

    # Create a unique host name for the config
    local config_name="rht-lab"

    # Create a temporary file
    local tmp_config="${SSH_CONFIG}.tmp"
    
    # Remove any existing config for this host while copying other configs
    awk -v host="$config_name" '
        /^Host '"$config_name"'$/ { skip=1; next }
        /^$/ { if (skip) { skip=0 }; if (!skip) print; next }
        /^Host / { skip=0 }
        !skip { print }
    ' "$SSH_CONFIG" > "$tmp_config"

    # Add new config entry
    {
        echo ""
        echo "# Red Hat Training Lab Environment - Added by login.sh"
        echo "Host ${config_name}"
        echo "    HostName ${student_host}"
        echo "    User ${student_user}"
        echo "    Port ${STUDENT_PORT}"
        echo "    IdentityFile ${FOUND_KEY_PATH}"
        echo "    ProxyJump ${cloud_user_host}:${cloud_port}"
        echo "    StrictHostKeyChecking no"
        echo "    UserKnownHostsFile /dev/null"
        echo "    LogLevel ERROR"
        echo ""
    } >> "$tmp_config"

    # Replace original with new config
    mv "$tmp_config" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    echo "SSH config updated. You can now also connect using: ssh ${config_name}"
    
    # Update status after successful config update
    update_status "ssh_config_updated" "true"
    
    return 0
}

# Function to create the connection alias
create_alias() {
    # Check if alias is already created
    if [ "$(get_status "alias_created")" = "true" ] && [ $SOURCED -eq 1 ]; then
        echo "Connection alias already created"
        return 0
    fi
    
    # Load saved environment if available
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null
    fi
    
    # If key path not set, use default
    if [ -z "$FOUND_KEY_PATH" ]; then
        FOUND_KEY_PATH="$KEY_PATH_IN_SSH"
    fi
    
    # Ensure all variables have values
    if [ -z "$CLOUD_JUMP" ] || [ -z "$STUDENT_TARGET" ] || [ -z "$STUDENT_PORT" ] || [ -z "$FOUND_KEY_PATH" ]; then
        echo "Error: Missing connection details. Please run setup first."
        echo "  CLOUD_JUMP: $CLOUD_JUMP"
        echo "  STUDENT_TARGET: $STUDENT_TARGET"
        echo "  STUDENT_PORT: $STUDENT_PORT"
        echo "  FOUND_KEY_PATH: $FOUND_KEY_PATH"
        return 1
    fi

    # Update SSH config file
    update_ssh_config || echo "Warning: Failed to update SSH config file"
    
    # Create the alias if script is sourced
    if [ "$SOURCED" -eq 1 ]; then
        # Define the alias for rh-connect with host key checking disabled and proper quoting
        alias rh-connect="ssh -i \"$FOUND_KEY_PATH\" -J \"$CLOUD_JUMP\" \"$STUDENT_TARGET\" -p \"$STUDENT_PORT\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        
        echo "Alias created: rh-connect"
        
        # Update status after successful alias creation
        update_status "alias_created" "true"
        
        return 0
    else
        echo "Note: Script executed directly. To create the alias, use 'source $(basename "$0")'"
        return 0  # Return success so script continues
    fi
}

# Function to show connection string (for both sourced and direct execution)
show_connection() {
    # Load saved environment if available
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null
    fi
    
    # If key path not set, use default
    if [ -z "$FOUND_KEY_PATH" ]; then
        FOUND_KEY_PATH="$SSH_DIR/$KEY_NAME"
    fi
    
    # Ensure all variables have values
    if [ -z "$CLOUD_JUMP" ] || [ -z "$STUDENT_TARGET" ] || [ -z "$STUDENT_PORT" ] || [ -z "$FOUND_KEY_PATH" ]; then
        echo "Error: Missing connection details. Please run setup or start first."
        echo "Debug information:"
        echo "  CLOUD_JUMP: $CLOUD_JUMP"
        echo "  STUDENT_TARGET: $STUDENT_TARGET"
        echo "  STUDENT_PORT: $STUDENT_PORT"
        echo "  FOUND_KEY_PATH: $FOUND_KEY_PATH"
        return 1
    fi
    
    # Clean up and track known_hosts entries
    read -r cloud_host student_host <<< "$(get_connection_hosts)"
    manage_known_hosts "clean" "$cloud_host" "$student_host"
    manage_known_hosts "add" "$cloud_host" "$student_host"
    
    # Build the SSH command with exact format
    SSH_CMD="ssh -i $FOUND_KEY_PATH -J $CLOUD_JUMP $STUDENT_TARGET -p $STUDENT_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    # For debugging, show the exact command that will be used
    echo "Debug: SSH command that will be used:"
    echo "$SSH_CMD"
    
    # Display connection info based on whether script is sourced
    if [ "$SOURCED" -eq 1 ]; then
        # Create the alias with exact command format
        alias rh-connect="ssh -i \"$FOUND_KEY_PATH\" -J \"$CLOUD_JUMP\" \"$STUDENT_TARGET\" -p \"$STUDENT_PORT\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
        echo ""
        echo "-----------------------------------------------------"
        echo " Lab SSH Setup Complete"
        echo " To connect: rh-connect"
        echo "-----------------------------------------------------"
    else
        echo ""
        echo "-----------------------------------------------------"
        echo " Lab SSH Setup Complete"
        echo " To connect: $SSH_CMD"
        echo "-----------------------------------------------------"
        
        # If this is the connect command, actually run the SSH command
        if [[ "$1" == "connect" ]]; then
            echo "Connecting..."
            # Execute the SSH command directly
            ssh -i "$FOUND_KEY_PATH" \
                -J "$CLOUD_JUMP" \
                "$STUDENT_TARGET" \
                -p "$STUDENT_PORT" \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR
            local ssh_exit=$?
            
            # If connection was successful, add the hosts to our managed list
            if [ $ssh_exit -eq 0 ]; then
                manage_known_hosts "add" "$cloud_host" "$student_host"
            fi
            
            return $ssh_exit
        fi
    fi
    
    return 0
}

# Function to open Cursor IDE with SSH connection
open_cursor() {
    # Check if cursor command exists
    if ! command -v cursor >/dev/null 2>&1; then
        error_message "Cursor command not found. Please ensure Cursor IDE is installed and available in PATH."
        return 1
    fi

    # Load saved environment if available
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE" 2>/dev/null
    fi

    # Ensure all variables have values
    if [ -z "$CLOUD_JUMP" ] || [ -z "$STUDENT_TARGET" ] || [ -z "$STUDENT_PORT" ] || [ -z "$FOUND_KEY_PATH" ]; then
        echo "Error: Missing connection details. Please run setup first."
        echo "  CLOUD_JUMP: $CLOUD_JUMP"
        echo "  STUDENT_TARGET: $STUDENT_TARGET"
        echo "  STUDENT_PORT: $STUDENT_PORT"
        echo "  FOUND_KEY_PATH: $FOUND_KEY_PATH"
        return 1
    fi

    # Extract student host and port from target
    local student_host=${STUDENT_TARGET#*@}

    # Ensure SSH config is up to date
    update_ssh_config || {
        echo "Warning: Failed to update SSH config. Cursor may not connect properly."
        return 1
    }

    echo "Opening Cursor IDE connected to rht-lab..."
    # Use the proper Cursor remote command format with host:port
    cursor --remote "${student_host}:${STUDENT_PORT}"
    return $?
}

# Function to show script status
show_status() {
    if [ ! -f "$STATUS_FILE" ]; then
        echo "No status information available. Run setup first."
        return 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        echo "Current Status:"
        echo "=============="
        jq -r '
            "Last Run: \(.last_run)",
            "Sourced: \(.sourced)",
            "\nSteps:",
            (.steps | to_entries[] | "  \(.key): \(.value)"),
            "\nConnection Details:",
            (.connection | to_entries[] | "  \(.key): \(.value)")'
        "$STATUS_FILE"
    else
        echo "Current Status (basic view):"
        echo "=========================="
        cat "$STATUS_FILE"
    fi
}

# --- Main Command Dispatcher ---
run_command() {
    local command="setup"  # Default command
    
    # If first argument is a recognized command, use it
    if [ -n "$1" ] && [[ "$1" == "setup" || "$1" == "start" || "$1" == "connect" || "$1" == "cursor" || "$1" == "status" ]]; then
        command="$1"
    fi
    
    # For 'connect', 'start', and 'cursor', try to load saved configuration first
    if [[ "$command" == "connect" || "$command" == "start" || "$command" == "cursor" ]]; then
        if [ -f "$ENV_FILE" ]; then
            source "$ENV_FILE" 2>/dev/null
        fi
    fi
    
    case "$command" in
        setup)
            check_config "$@" || return 1
            setup_ssh_key || return 1
            create_alias || return 1
            ;;
        start)
            if [ "$(get_status "key_setup")" != "true" ]; then
                echo "SSH key not setup. Please run setup first."
                return 1
            fi
            check_config "$@" || return 1
            create_alias || return 1
            ;;
        connect)
            if [ "$(get_status "config_checked")" != "true" ] || [ "$(get_status "key_setup")" != "true" ]; then
                echo "Connection not configured. Please run setup first."
                return 1
            fi
            show_connection "$command"
            ;;
        cursor)
            if [ "$(get_status "config_checked")" != "true" ] || [ "$(get_status "key_setup")" != "true" ]; then
                echo "Setting up connection details..."
                check_config "$@" || return 1
                setup_ssh_key || return 1
                create_alias || return 1
            fi
            open_cursor
            ;;
        status)
            show_status
            ;;
        *)
            error_message "Unknown command: $command"
            return 1
            ;;
    esac
    
    return 0
}

# --- Script Execution ---

# Check for --help option regardless of how the script is invoked
for arg in "$@"; do
    if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
        show_help
        if [ "$SOURCED" -eq 1 ]; then
            return 0
        else
            exit 0
        fi
    fi
done

# Handle script name detection when placed in PATH
if [ "$(basename "$0")" != "login.sh" ] && [ "$SOURCED" -eq 0 ]; then
    # Script is being called by another name (e.g., role-login)
    run_command "$@"
    exit $?
fi

# Run the appropriate command
run_command "$@"

# If script is sourced and no errors, return success
if [ "$SOURCED" -eq 1 ]; then
    return 0
fi 