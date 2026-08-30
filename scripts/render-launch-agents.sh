#!/bin/zsh

set -euo pipefail

if (( $# < 3 || $# > 4 )); then
  print -u2 "Usage: $0 OUTPUT_DIRECTORY RUNTIME_DIRECTORY LOG_DIRECTORY [CONTAINER_CLI_PATH]"
  exit 64
fi

readonly output_directory="$1"
readonly runtime_directory="$2"
readonly log_directory="$3"
readonly container_cli_path="${4:-/usr/local/bin/container}"
readonly service_plist="$output_directory/com.msj.container-gui.plist"
readonly watchdog_plist="$output_directory/com.msj.container-gui.watchdog.plist"
readonly service_path="$runtime_directory/ContainerGUI"
readonly watchdog_path="$runtime_directory/container-gui-watchdog.sh"
readonly command_path="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

/bin/mkdir -p "$output_directory"

/usr/bin/plutil -create xml1 "$service_plist"
/usr/bin/plutil -insert Label -string "com.msj.container-gui" "$service_plist"
/usr/bin/plutil -insert ProgramArguments -array "$service_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$service_path" "$service_plist"
/usr/bin/plutil -insert WorkingDirectory -string "$runtime_directory" "$service_plist"
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$service_plist"
/usr/bin/plutil -insert EnvironmentVariables.CONTAINER_GUI_PORT -string "8787" "$service_plist"
/usr/bin/plutil -insert EnvironmentVariables.CONTAINER_GUI_CLI_PATH -string "$container_cli_path" "$service_plist"
/usr/bin/plutil -insert EnvironmentVariables.PATH -string "$command_path" "$service_plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$service_plist"
/usr/bin/plutil -insert KeepAlive -bool true "$service_plist"
/usr/bin/plutil -insert ThrottleInterval -integer 5 "$service_plist"
/usr/bin/plutil -insert ProcessType -string "Background" "$service_plist"
/usr/bin/plutil -insert StandardOutPath -string "$log_directory/service.log" "$service_plist"
/usr/bin/plutil -insert StandardErrorPath -string "$log_directory/service-error.log" "$service_plist"

/usr/bin/plutil -create xml1 "$watchdog_plist"
/usr/bin/plutil -insert Label -string "com.msj.container-gui.watchdog" "$watchdog_plist"
/usr/bin/plutil -insert ProgramArguments -array "$watchdog_plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "/bin/zsh" "$watchdog_plist"
/usr/bin/plutil -insert ProgramArguments.1 -string "$watchdog_path" "$watchdog_plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$watchdog_plist"
/usr/bin/plutil -insert StartInterval -integer 30 "$watchdog_plist"
/usr/bin/plutil -insert ProcessType -string "Background" "$watchdog_plist"
/usr/bin/plutil -insert StandardOutPath -string "$log_directory/watchdog.log" "$watchdog_plist"
/usr/bin/plutil -insert StandardErrorPath -string "$log_directory/watchdog-error.log" "$watchdog_plist"

/usr/bin/plutil -lint "$service_plist" "$watchdog_plist"
