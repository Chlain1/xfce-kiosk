#!/bin/bash

# Variables
KIOSK_URL="https://stuve.de"
USER_HOME="/home/$(whoami)"
KIOSK_SCRIPT_PATH="/usr/local/bin/kiosk.sh"
WATCHDOG_SCRIPT_PATH="$USER_HOME/chromium_cron_watchdog.sh"
SERVICE_PATH="/etc/systemd/system/kiosk.service"
XFCE_KEYBOARD_XML="$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

# Function fo installing xdotool and chromium
install_dependencies() {
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y chromium xdotool xmlstarlet
}

# Create the script for opening Chromium in kiosk mode
create_kiosk_script() {
    echo "Create the script that starts Chromium in kios mode..."
    sudo bash -c "cat > $KIOSK_SCRIPT_PATH" << EOL
#!/bin/bash
# Launching Chromium in kiosk mode on the display
/usr/bin/chromium --noerrdialogs --disable-infobars --kiosk "$KIOSK_URL"
EOL
    sudo chmod +x $KIOSK_SCRIPT_PATH
}

# Creating the systemd service file
create_systemd_service() {
    echo "Creating the systemd service for the kiosk mode..."
    sudo bash -c "cat > $SERVICE_PATH" << EOL
[Unit]
Description=Kiosk Mode for Chromium
After=systemd-user-sessions.service getty@tty1.service

[Service]
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$USER_HOME/.Xauthority"
ExecStart=$KIOSK_SCRIPT_PATH
Restart=always
User=$(whoami)
Group=$(whoami)

[Install]
WantedBy=multi-user.target
EOL
    sudo systemctl enable kiosk.service
}

# Creating the monitoring script for the Chromium job
create_watchdog_script() {
    echo "Creating the monitoring script for Chromium..."
    cat > $WATCHDOG_SCRIPT_PATH << EOL
#!/bin/bash

# Verifying if the kiosk service is active
if ! systemctl is-active --quiet kiosk.service; then
    echo "\$(date): The service Chromium in kiosk mode isn't active. Relaunching..." >> $USER_HOME/chromium_watchdog.log
    # Relaunching the kiosk service
    sudo systemctl start kiosk.service
else
    echo "\$(date): The service Chromium in kiosk mode is working correctly." >> $USER_HOME/chromium_watchdog.log
    # Refreshes the page if the service is active
    xdotool search --onlyvisible --class "chromium" key F5
fi
EOL
    chmod +x $WATCHDOG_SCRIPT_PATH
}

# Adding the cron task
add_cron_job() {
    echo "Adding a cron job to monitor Chromium..."
    (crontab -l 2>/dev/null; echo "*/30 * * * * $WATCHDOG_SCRIPT_PATH") | crontab -
}

# Configuring the keyboard shortcut to exit kiosk mode
configure_xfce_shortcut() {
    echo "Configuring the keyboard shortcut to exit kiosk mode..."
    # Creates the XML file for the shortcuts if it does not already exist
    if [ ! -f "$XFCE_KEYBOARD_XML" ]; then
        mkdir -p "$(dirname "$XFCE_KEYBOARD_XML")"
        cat > "$XFCE_KEYBOARD_XML" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
</channel>
EOL
    fi

    # Add the shortcut Ctrl+Alt+Delete to stop the kiosk service
    xmlstarlet ed -L -s "/channel" -t elem -n "property" -v "" \
        -i "/channel/property[not(@name='custom')]" -t attr -n "name" -v "custom" \
        -i "/channel/property[@name='custom']" -t attr -n "type" -v "empty" \
        -s "/channel/property[@name='custom']" -t elem -n "property" -v "" \
        -i "/channel/property[@name='custom']/property[not(@name='Ctrl+Alt+Delete')]" -t attr -n "name" -v "Ctrl+Alt+Delete" \
        -i "/channel/property[@name='custom']/property[@name='Ctrl+Alt+Delete']" -t attr -n "type" -v "string" \
        -s "/channel/property[@name='custom']/property[@name='Ctrl+Alt+Delete']" -t elem -n "property" -v "sudo systemctl stop kiosk.service" \
        "$XFCE_KEYBOARD_XML"
}

# Executing the steps
install_dependencies
create_kiosk_script
create_systemd_service
create_watchdog_script
add_cron_job
configure_xfce_shortcut

echo "Configuration complete! Restart your computer to apply the changes."
