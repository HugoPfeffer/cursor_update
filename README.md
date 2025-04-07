# SSH Automation for Ephemeral Lab VM

A bash script to automate SSH connections to ephemeral lab virtual machines with dynamic IPs and ports. This tool simplifies the process of setting up and managing SSH connections, particularly useful for lab environments where connection details change frequently.

## Features

- **Automated SSH Key Management**
  - Moves SSH key from Downloads to ~/.ssh
  - Sets correct permissions (600)
  - Adds key to ssh-agent automatically
  - Validates key existence and permissions

- **Connection Management**
  - Stores connection details for reuse
  - Handles jump host configurations
  - Supports dynamic IP addresses and ports
  - Manages SSH config file entries

- **Cursor IDE Integration**
  - Direct launch with remote connection
  - Automatic SSH config generation
  - Quick connection testing
  - Fallback manual connection instructions

- **Security Features**
  - Proper key permissions enforcement
  - Secure SSH config file handling
  - Temporary known_hosts management
  - Batch mode for non-interactive operations

## Usage

### Basic Commands

```bash
# Initial setup with connection
./login.sh setup "cloud-user@jump_host_ip:jump_port student@target_host_ip -p target_port"

# Connect using stored configuration
./login.sh connect

# Connect with new configuration
./login.sh connect "cloud-user@jump_host_ip:jump_port student@target_host_ip -p target_port"

# Open in Cursor IDE
./login.sh cursor "cloud-user@jump_host_ip:jump_port student@target_host_ip -p target_port"

# Check current status
./login.sh status

# Clean up everything
./login.sh clean
```

### Connection String Format

The script expects connection strings in the following format:
```bash
"cloud-user@<jump_host_ip>:<jump_host_port> student@<target_host_ip> -p <target_port>"
```

Example:
```bash
"cloud-user@148.62.94.60:22022 student@172.25.252.1 -p 53009"
```

## Commands in Detail

### `setup`
- Moves SSH key from Downloads to ~/.ssh
- Sets correct permissions (600)
- Adds key to ssh-agent
- Optionally stores connection details
- Can immediately connect after setup

### `connect`
- Uses stored or provided connection details
- Handles host key verification automatically
- Creates temporary SSH configurations
- Supports jump host connections

### `cursor`
- Sets up SSH configuration for Cursor IDE
- Validates existing configurations
- Tests connection without full login
- Launches Cursor IDE with remote connection
- Provides fallback manual connection steps

### `clean`
- Removes SSH key from agent
- Removes key file from ~/.ssh
- Removes stored connection details
- Cleans up temporary configurations

### `status`
Shows current configuration status:
- SSH key presence and permissions
- SSH agent status
- Connection configuration status
- Known hosts entries count
- sshpass availability

## Configuration Files

- SSH Key: `~/.ssh/rht_classroom.rsa`
- Config Directory: `~/.config/role_script_ssh/`
- Connection Config: `~/.config/role_script_ssh/connection.conf`
- SSH Config: `~/.ssh/config`

## Security Notes

1. The script automatically handles:
   - SSH key setup and permissions
   - Host key verification
   - Connection detail storage
   - Secure config file permissions

2. All sensitive files are stored with 600 permissions
3. Temporary known_hosts file used to avoid conflicts
4. Non-interactive batch mode for automated operations

## Requirements

- Bash shell
- SSH client
- sshpass (optional, auto-installed if needed)
- Cursor IDE (for remote development features)

## Installation

1. Clone or download the script
2. Make it executable:
   ```bash
   chmod +x login.sh
   ```
3. Place your SSH key in `~/Downloads/rht_classroom.rsa`
4. Run the script with desired command

## Troubleshooting

1. If connection fails:
   - Check if SSH key exists and has correct permissions
   - Verify connection string format
   - Ensure jump host is accessible
   - Check target host is reachable through jump host

2. For Cursor IDE issues:
   - Verify SSH configuration in ~/.ssh/config
   - Check SSH key permissions
   - Try manual connection steps provided by script

## Contributing

Feel free to submit issues and enhancement requests!