#!/bin/zsh

set -euo pipefail

readonly user_id="$(/usr/bin/id -u)"
readonly launch_domain="gui/$user_id"
readonly service_label="com.msj.container-gui"
readonly watchdog_label="com.msj.container-gui.watchdog"
readonly launch_agents_directory="$HOME/Library/LaunchAgents"

/bin/launchctl bootout "$launch_domain/$watchdog_label" 2>/dev/null || true
/bin/launchctl bootout "$launch_domain/$service_label" 2>/dev/null || true
/bin/rm -f \
  "$launch_agents_directory/$watchdog_label.plist" \
  "$launch_agents_directory/$service_label.plist"

print "Container GUI LaunchAgents were removed."
print "Installed runtime versions and logs were retained for recovery."
