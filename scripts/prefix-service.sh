#!/bin/bash

# Prefix Service Management Script
# Supports both macOS (LaunchAgent) and Linux (systemd)

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "darwin"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS=$(detect_os)

# macOS-specific variables
PLIST_NAME="com.prefix"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist"
DOMAIN="gui/$(id -u)"

# Linux-specific variables
SYSTEMD_SERVICE_NAME="prefix.service"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SYSTEMD_SERVICE_PATH="$SYSTEMD_USER_DIR/$SYSTEMD_SERVICE_NAME"

# Common variables
CONFIG_FILE="$HOME/.config/prefix/prefix.yaml"

# Find binary path
find_binary() {
    if command -v prefix &> /dev/null; then
        which prefix
    elif [ -f "$(brew --prefix 2>/dev/null)/bin/prefix" ]; then
        echo "$(brew --prefix)/bin/prefix"
    elif [ -f "/usr/local/bin/prefix" ]; then
        echo "/usr/local/bin/prefix"
    elif [ -f "$HOME/.local/bin/prefix" ]; then
        echo "$HOME/.local/bin/prefix"
    else
        echo ""
    fi
}

BINARY_PATH=$(find_binary)

# macOS LaunchAgent functions
is_service_loaded_macos() {
    if launchctl list "$DOMAIN/$PLIST_NAME" &>/dev/null; then
        return 0
    elif launchctl list | grep -q "$PLIST_NAME"; then
        return 0
    else
        return 1
    fi
}

start_service_macos() {
    if launchctl bootstrap "$DOMAIN" "$PLIST_PATH" 2>/dev/null; then
        return 0
    elif launchctl load -w "$PLIST_PATH" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

stop_service_macos() {
    if launchctl bootout "$DOMAIN/$PLIST_NAME" 2>/dev/null; then
        return 0
    elif launchctl unload "$PLIST_PATH" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Linux systemd functions
is_service_loaded_linux() {
    systemctl --user is-active --quiet "$SYSTEMD_SERVICE_NAME" 2>/dev/null
}

start_service_linux() {
    systemctl --user start "$SYSTEMD_SERVICE_NAME" 2>/dev/null
}

stop_service_linux() {
    systemctl --user stop "$SYSTEMD_SERVICE_NAME" 2>/dev/null
}

enable_service_linux() {
    systemctl --user enable "$SYSTEMD_SERVICE_NAME" 2>/dev/null
}

# Install functions
install_macos() {
    echo "Installing prefix LaunchAgent (macOS)..."
    
    if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
        echo "Error: prefix binary not found"
        echo "Please install prefix first"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Warning: Config file not found at $CONFIG_FILE"
        echo "Please create and configure $CONFIG_FILE before starting the service"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    mkdir -p "$LAUNCH_AGENTS_DIR"
    
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/prefix.log</string>
    
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/prefix.error.log</string>
    
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>Nice</key>
    <integer>1</integer>
</dict>
</plist>
EOF
    
    if launchctl bootstrap gui/$(id -u) "$PLIST_PATH" 2>/dev/null; then
        echo "✓ LaunchAgent installed and started (bootstrap)"
    elif launchctl load -w "$PLIST_PATH" 2>/dev/null; then
        echo "✓ LaunchAgent installed and started (load)"
    else
        echo "⚠ LaunchAgent installed but failed to start automatically"
        echo "  Try: launchctl load -w $PLIST_PATH"
    fi
    echo "  Service will automatically start on boot"
    echo "  Logs: ~/Library/Logs/prefix.log"
}

install_linux() {
    echo "Installing prefix systemd service (Linux)..."
    
    if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
        echo "Error: prefix binary not found"
        echo "Please install prefix first"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Warning: Config file not found at $CONFIG_FILE"
        echo "Please create and configure $CONFIG_FILE before starting the service"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    if ! systemctl --user --version &>/dev/null; then
        echo "Error: systemd user services not available"
        echo "This script requires systemd"
        exit 1
    fi
    
    mkdir -p "$SYSTEMD_USER_DIR"
    
    cat > "$SYSTEMD_SERVICE_PATH" <<EOF
[Unit]
Description=Prefix File Organizer
After=network.target

[Service]
Type=simple
ExecStart=$BINARY_PATH
Restart=always
RestartSec=10
WorkingDirectory=$HOME
StandardOutput=append:$HOME/.config/prefix/prefix.log
StandardError=append:$HOME/.config/prefix/prefix.error.log

[Install]
WantedBy=default.target
EOF
    
    systemctl --user daemon-reload
    
    if systemctl --user enable "$SYSTEMD_SERVICE_NAME" 2>/dev/null; then
        echo "✓ Systemd service installed and enabled"
    else
        echo "✗ Failed to enable service"
        exit 1
    fi
    
    if systemctl --user start "$SYSTEMD_SERVICE_NAME" 2>/dev/null; then
        echo "✓ Service started"
    else
        echo "⚠ Service installed but failed to start"
        echo "  Check logs: journalctl --user -u $SYSTEMD_SERVICE_NAME"
    fi
    
    echo "  Service will automatically start on boot"
    echo "  Logs: ~/.config/prefix/prefix.log"
    echo ""
    echo "Note: To enable user services at boot, ensure logind is configured:"
    echo "  sudo loginctl enable-linger \$(whoami)"
}

# Main command handling
case "$1" in
    install)
        if [ "$OS" = "darwin" ]; then
            install_macos
        elif [ "$OS" = "linux" ]; then
            install_linux
        else
            echo "Error: Unsupported operating system"
            exit 1
        fi
        ;;
    
    uninstall)
        if [ "$OS" = "darwin" ]; then
            echo "Uninstalling prefix LaunchAgent..."
            if [ -f "$PLIST_PATH" ]; then
                stop_service_macos 2>/dev/null || true
                rm -f "$PLIST_PATH"
                echo "✓ LaunchAgent uninstalled"
            else
                echo "LaunchAgent not found"
            fi
        elif [ "$OS" = "linux" ]; then
            echo "Uninstalling prefix systemd service..."
            if [ -f "$SYSTEMD_SERVICE_PATH" ]; then
                systemctl --user stop "$SYSTEMD_SERVICE_NAME" 2>/dev/null || true
                systemctl --user disable "$SYSTEMD_SERVICE_NAME" 2>/dev/null || true
                rm -f "$SYSTEMD_SERVICE_PATH"
                systemctl --user daemon-reload
                echo "✓ Systemd service uninstalled"
            else
                echo "Service not found"
            fi
        else
            echo "Error: Unsupported operating system"
            exit 1
        fi
        ;;
    
    start)
        if [ "$OS" = "darwin" ]; then
            if [ ! -f "$PLIST_PATH" ]; then
                echo "Error: LaunchAgent not installed"
                echo "Run: prefix-service install"
                exit 1
            fi
            if is_service_loaded_macos; then
                echo "Service is already running"
            elif start_service_macos; then
                echo "✓ Service started"
            else
                echo "✗ Failed to start service"
                exit 1
            fi
        elif [ "$OS" = "linux" ]; then
            if [ ! -f "$SYSTEMD_SERVICE_PATH" ]; then
                echo "Error: Service not installed"
                echo "Run: prefix-service install"
                exit 1
            fi
            if is_service_loaded_linux; then
                echo "Service is already running"
            elif start_service_linux; then
                echo "✓ Service started"
            else
                echo "✗ Failed to start service"
                exit 1
            fi
        fi
        ;;
    
    stop)
        if [ "$OS" = "darwin" ]; then
            if [ ! -f "$PLIST_PATH" ]; then
                echo "Error: LaunchAgent not installed"
                exit 1
            fi
            if ! is_service_loaded_macos; then
                echo "Service is not running"
            elif stop_service_macos; then
                echo "✓ Service stopped"
            else
                echo "✗ Failed to stop service"
            fi
        elif [ "$OS" = "linux" ]; then
            if [ ! -f "$SYSTEMD_SERVICE_PATH" ]; then
                echo "Error: Service not installed"
                exit 1
            fi
            if ! is_service_loaded_linux; then
                echo "Service is not running"
            elif stop_service_linux; then
                echo "✓ Service stopped"
            else
                echo "✗ Failed to stop service"
            fi
        fi
        ;;
    
    restart)
        echo "Restarting prefix service..."
        if [ "$OS" = "darwin" ]; then
            if [ ! -f "$PLIST_PATH" ]; then
                echo "Error: LaunchAgent not installed"
                exit 1
            fi
            stop_service_macos 2>/dev/null || true
            sleep 1
            if start_service_macos; then
                echo "✓ Service restarted"
            else
                echo "✗ Failed to restart service"
                exit 1
            fi
        elif [ "$OS" = "linux" ]; then
            if [ ! -f "$SYSTEMD_SERVICE_PATH" ]; then
                echo "Error: Service not installed"
                exit 1
            fi
            systemctl --user restart "$SYSTEMD_SERVICE_NAME" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✓ Service restarted"
            else
                echo "✗ Failed to restart service"
                exit 1
            fi
        fi
        ;;
    
    status)
        if [ "$OS" = "darwin" ]; then
            if [ ! -f "$PLIST_PATH" ]; then
                echo "Status: Not installed"
                exit 0
            fi
            
            if is_service_loaded_macos; then
                echo "Status: Running"
                PID=$(launchctl list "$DOMAIN/$PLIST_NAME" 2>/dev/null | tail -1 | awk '{print $1}' || \
                      launchctl list | grep "$PLIST_NAME" | awk '{print $1}' || echo "N/A")
                if [ "$PID" != "N/A" ] && [ "$PID" != "-" ]; then
                    echo "PID: $PID"
                fi
            else
                echo "Status: Stopped"
            fi
            
            echo ""
            echo "Config: $CONFIG_FILE"
            if [ -f "$CONFIG_FILE" ]; then
                echo "  ✓ Config file exists"
            else
                echo "  ✗ Config file missing"
            fi
            
            echo ""
            echo "Logs:"
            if [ -f "$HOME/Library/Logs/prefix.log" ]; then
                LOG_SIZE=$(ls -lh "$HOME/Library/Logs/prefix.log" | awk '{print $5}')
                echo "  Output: $HOME/Library/Logs/prefix.log ($LOG_SIZE)"
            else
                echo "  Output: $HOME/Library/Logs/prefix.log (not created yet)"
            fi
            if [ -f "$HOME/Library/Logs/prefix.error.log" ]; then
                ERR_SIZE=$(ls -lh "$HOME/Library/Logs/prefix.error.log" | awk '{print $5}')
                echo "  Errors: $HOME/Library/Logs/prefix.error.log ($ERR_SIZE)"
            else
                echo "  Errors: $HOME/Library/Logs/prefix.error.log (no errors)"
            fi
            if [ -f "$HOME/.config/prefix/app.log" ]; then
                APP_LOG_SIZE=$(ls -lh "$HOME/.config/prefix/app.log" | awk '{print $5}')
                echo "  App log: $HOME/.config/prefix/app.log ($APP_LOG_SIZE)"
            else
                echo "  App log: $HOME/.config/prefix/app.log (not created yet)"
            fi
        elif [ "$OS" = "linux" ]; then
            if [ ! -f "$SYSTEMD_SERVICE_PATH" ]; then
                echo "Status: Not installed"
                exit 0
            fi
            
            systemctl --user is-active --quiet "$SYSTEMD_SERVICE_NAME" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "Status: Running"
                PID=$(systemctl --user show -p MainPID --value "$SYSTEMD_SERVICE_NAME" 2>/dev/null || echo "N/A")
                if [ "$PID" != "N/A" ] && [ "$PID" != "0" ]; then
                    echo "PID: $PID"
                fi
            else
                echo "Status: Stopped"
            fi
            
            echo ""
            echo "Config: $CONFIG_FILE"
            if [ -f "$CONFIG_FILE" ]; then
                echo "  ✓ Config file exists"
            else
                echo "  ✗ Config file missing"
            fi
            
            echo ""
            echo "Logs:"
            if [ -f "$HOME/.config/prefix/prefix.log" ]; then
                LOG_SIZE=$(ls -lh "$HOME/.config/prefix/prefix.log" | awk '{print $5}')
                echo "  Output: $HOME/.config/prefix/prefix.log ($LOG_SIZE)"
            else
                echo "  Output: $HOME/.config/prefix/prefix.log (not created yet)"
            fi
            if [ -f "$HOME/.config/prefix/prefix.error.log" ]; then
                ERR_SIZE=$(ls -lh "$HOME/.config/prefix/prefix.error.log" | awk '{print $5}')
                echo "  Errors: $HOME/.config/prefix/prefix.error.log ($ERR_SIZE)"
            else
                echo "  Errors: $HOME/.config/prefix/prefix.error.log (no errors)"
            fi
            if [ -f "$HOME/.config/prefix/app.log" ]; then
                APP_LOG_SIZE=$(ls -lh "$HOME/.config/prefix/app.log" | awk '{print $5}')
                echo "  App log: $HOME/.config/prefix/app.log ($APP_LOG_SIZE)"
            else
                echo "  App log: $HOME/.config/prefix/app.log (not created yet)"
            fi
        fi
        ;;
    
    logs)
        if [ "$OS" = "darwin" ]; then
            if [ -f "$HOME/Library/Logs/prefix.log" ]; then
                tail -f "$HOME/Library/Logs/prefix.log"
            else
                echo "Log file not found. Service may not be running."
            fi
        elif [ "$OS" = "linux" ]; then
            if [ -f "$SYSTEMD_SERVICE_PATH" ]; then
                journalctl --user -u "$SYSTEMD_SERVICE_NAME" -f
            else
                echo "Service not installed. Run: prefix-service install"
            fi
        fi
        ;;
    
    *)
        echo "Usage: $0 {install|uninstall|start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  install   - Install and start the service"
        echo "  uninstall - Remove the service"
        echo "  start    - Start the service"
        echo "  stop     - Stop the service"
        echo "  restart  - Restart the service"
        echo "  status   - Show service status"
        echo "  logs     - Follow log output"
        exit 1
        ;;
esac
