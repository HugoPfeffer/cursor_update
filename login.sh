#!/bin/bash

# Script to automate lab connection process
# This script sets up the SSH key and connects to the lab environment

# Default values for key path only - connection parameters must be provided
SSH_KEY_PATH="$HOME/Downloads/rht_classroom.rsa"
SSH_TARGET=""
LAB_SERVER=""
LAB_PORT=""
SHELL_RC=""

# Determine which shell configuration file to use
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Display help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Automates the process of setting up SSH keys and connecting to the lab environment."
    echo ""
    echo "Options:"
    echo "  -k, --key PATH       Path to the SSH key (default: ~/Downloads/rht_classroom.rsa)"
    echo "  -h, --help           Display this help message and exit"
    echo "  -t, --target IP:PORT Set the SSH jump target (required if not in interactive mode)"
    echo "  -s, --server IP      Set the lab server IP (required if not in interactive mode)"
    echo "  -p, --port PORT      Set the lab server port (required if not in interactive mode)"
    echo "  -a, --add-alias      Add an alias to your shell configuration"
    echo ""
    echo "Example:"
    echo "  $0 --key ~/custom/path/rht_classroom.rsa --target 148.62.94.60:22022 --server 172.25.252.1 --port 53009"
}

# Process command line arguments
INTERACTIVE=true
ADD_ALIAS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -t|--target)
            SSH_TARGET="cloud-user@$2"
            INTERACTIVE=false
            shift 2
            ;;
        -s|--server)
            LAB_SERVER="student@$2"
            INTERACTIVE=false
            shift 2
            ;;
        -p|--port)
            LAB_PORT="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -a|--add-alias)
            ADD_ALIAS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Interactive mode: prompt for connection details
if [ "$INTERACTIVE" = true ]; then
    # Extract values for displaying in prompt if they exist
    TARGET_IP=""
    TARGET_PORT=""
    SERVER_IP=""
    
    if [ -n "$SSH_TARGET" ]; then
        TARGET_IP=$(echo $SSH_TARGET | cut -d@ -f2 | cut -d: -f1)
        TARGET_PORT=$(echo $SSH_TARGET | cut -d@ -f2 | cut -d: -f2)
    fi
    
    if [ -n "$LAB_SERVER" ]; then
        SERVER_IP=$(echo $LAB_SERVER | cut -d@ -f2)
    fi
    
    # Prompt for values, make them required
    while [ -z "$TARGET_IP" ]; do
        read -p "Enter SSH jump host IP: " TARGET_IP
        if [ -z "$TARGET_IP" ]; then
            echo "Error: SSH jump host IP is required."
        fi
    done
    
    while [ -z "$TARGET_PORT" ]; do
        read -p "Enter SSH jump host port: " TARGET_PORT
        if [ -z "$TARGET_PORT" ]; then
            echo "Error: SSH jump host port is required."
        fi
    done
    
    while [ -z "$SERVER_IP" ]; do
        read -p "Enter lab server IP: " SERVER_IP
        if [ -z "$SERVER_IP" ]; then
            echo "Error: Lab server IP is required."
        fi
    done
    
    while [ -z "$LAB_PORT" ]; do
        read -p "Enter lab server port: " LAB_PORT
        if [ -z "$LAB_PORT" ]; then
            echo "Error: Lab server port is required."
        fi
    done
    
    # Update the variables with new values
    SSH_TARGET="cloud-user@$TARGET_IP:$TARGET_PORT"
    LAB_SERVER="student@$SERVER_IP"
    
    # Ask if user wants to add alias
    read -p "Would you like to add a connection alias to your shell configuration? (y/n) [n]: " ADD_ALIAS_ANSWER
    if [[ "$ADD_ALIAS_ANSWER" =~ ^[Yy]$ ]]; then
        ADD_ALIAS=true
    fi
else
    # If not in interactive mode, check if all required parameters are provided
    if [ -z "$SSH_TARGET" ]; then
        echo "Error: SSH jump target is required. Use --target option or run in interactive mode."
        exit 1
    fi
    
    if [ -z "$LAB_SERVER" ]; then
        echo "Error: Lab server IP is required. Use --server option or run in interactive mode."
        exit 1
    fi
    
    if [ -z "$LAB_PORT" ]; then
        echo "Error: Lab server port is required. Use --port option or run in interactive mode."
        exit 1
    fi
fi

# Check if the SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found at $SSH_KEY_PATH"
    echo "Please download the SSH key or specify the correct path with the -k option."
    exit 1
fi

# Create ~/.ssh directory if it doesn't exist
if [ ! -d "$HOME/.ssh" ]; then
    echo "Creating ~/.ssh directory..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

# Copy the SSH key to ~/.ssh directory
echo "Moving SSH key to ~/.ssh directory..."
cp "$SSH_KEY_PATH" "$HOME/.ssh/rht_classroom.rsa"

# Set proper permissions
echo "Setting permissions..."
chmod 0600 "$HOME/.ssh/rht_classroom.rsa"

# Add the key to the SSH agent
echo "Adding key to SSH agent..."
ssh-add "$HOME/.ssh/rht_classroom.rsa"

# Add alias if requested
if [ "$ADD_ALIAS" = true ] && [ -n "$SHELL_RC" ]; then
    # Extract components for the alias
    TARGET_IP=$(echo $SSH_TARGET | cut -d@ -f2 | cut -d: -f1)
    TARGET_PORT=$(echo $SSH_TARGET | cut -d: -f2)
    SERVER_IP=$(echo $LAB_SERVER | cut -d@ -f2)
    
    ALIAS_CMD="alias rh-connect='ssh -i ~/.ssh/rht_classroom.rsa -J cloud-user@$TARGET_IP:$TARGET_PORT student@$SERVER_IP -p $LAB_PORT'"
    
    # Check if alias already exists
    if grep -q "alias rh-connect" "$SHELL_RC"; then
        echo "Updating existing rh-connect alias in $SHELL_RC..."
        sed -i '/alias rh-connect/d' "$SHELL_RC"
    else
        echo "Adding rh-connect alias to $SHELL_RC..."
    fi
    
    echo "$ALIAS_CMD" >> "$SHELL_RC"
    echo "Alias added. You can now use 'rh-connect' to connect to the lab."
    echo "Please run 'source $SHELL_RC' to apply changes in your current shell."
fi

# Connect to the lab
echo "Connecting to the lab environment..."
echo "Using: ssh -i ~/.ssh/rht_classroom.rsa -J $SSH_TARGET $LAB_SERVER -p $LAB_PORT"
ssh -i "$HOME/.ssh/rht_classroom.rsa" -J "$SSH_TARGET" "$LAB_SERVER" -p "$LAB_PORT"

echo "If you were disconnected, you can reconnect by running this script again."
if [ "$ADD_ALIAS" = true ] && [ -n "$SHELL_RC" ]; then
    echo "Or simply type 'rh-connect' after sourcing your shell configuration."
fi
