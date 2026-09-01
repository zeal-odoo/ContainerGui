#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_root="${script_directory:h}"
readonly user_id="$(/usr/bin/id -u)"
readonly launch_domain="gui/$user_id"
readonly service_label="com.msj.container-gui"
readonly watchdog_label="com.msj.container-gui.watchdog"
readonly launch_agents_directory="$HOME/Library/LaunchAgents"
readonly support_root="$HOME/Library/Application Support/ContainerGUI"
readonly versions_directory="$support_root/versions"
readonly log_directory="$HOME/Library/Logs/ContainerGUI"
readonly swift_executable="$(/usr/bin/xcrun --find swift)"
readonly container_cli_path="${CONTAINER_GUI_CLI_PATH:-$(command -v container || true)}"
readonly app_version="$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' "$project_root/Sources/ContainerGUI/App/AppVersion.swift")"

if [[ -z "$container_cli_path" || ! -x "$container_cli_path" ]]; then
  print -u2 "Apple container CLI was not found. Install it or set CONTAINER_GUI_CLI_PATH."
  exit 69
fi

if [[ -z "$app_version" ]]; then
  print -u2 "Unable to read the Container GUI version."
  exit 65
fi

if [[ -L "$support_root" ]]; then
  print -u2 "Container GUI support path must not be a symbolic link."
  exit 65
fi
/bin/mkdir -p "$support_root"
/bin/chmod 700 "$support_root"

print "Building Container GUI $app_version in release mode..."
cd "$project_root"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  "$swift_executable" build -c release --product ContainerGUI

readonly build_directory="$(
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    "$swift_executable" build -c release --show-bin-path
)"
readonly built_service="$build_directory/ContainerGUI"
readonly built_resources="$build_directory/ContainerGUI_ContainerGUI.bundle"
readonly runtime_directory="$versions_directory/$app_version"

if [[ ! -x "$built_service" || ! -d "$built_resources" ]]; then
  print -u2 "Release binary or resource bundle is missing after the build."
  exit 66
fi

/bin/mkdir -p "$versions_directory" "$launch_agents_directory" "$log_directory"
readonly staging_directory="$(
  /usr/bin/mktemp -d "$versions_directory/.staging-$app_version.XXXXXX"
)"
trap '/bin/rm -rf "$staging_directory"' EXIT

/bin/cp "$built_service" "$staging_directory/ContainerGUI"
/bin/cp -R "$built_resources" "$staging_directory/ContainerGUI_ContainerGUI.bundle"
/bin/cp "$script_directory/container-gui-watchdog.sh" "$staging_directory/container-gui-watchdog.sh"
/bin/chmod 755 "$staging_directory/ContainerGUI" "$staging_directory/container-gui-watchdog.sh"

if [[ -e "$runtime_directory" ]]; then
  readonly previous_directory="$versions_directory/$app_version.previous.$(/bin/date +%Y%m%d%H%M%S).$$"
  /bin/mv "$runtime_directory" "$previous_directory"
fi
/bin/mv "$staging_directory" "$runtime_directory"
trap - EXIT

"$script_directory/render-launch-agents.sh" \
  "$launch_agents_directory" \
  "$runtime_directory" \
  "$log_directory" \
  "$container_cli_path"

/bin/launchctl bootout "$launch_domain/$watchdog_label" 2>/dev/null || true
/bin/launchctl bootout "$launch_domain/$service_label" 2>/dev/null || true

for wait_number in {1..10}; do
  if ! /usr/sbin/lsof -nP -iTCP:8787 -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  /bin/sleep 1
done

if /usr/sbin/lsof -nP -iTCP:8787 -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 "Port 8787 is still served by an unmanaged process. Stop that process and run this installer again."
  exit 70
fi

bootstrap_with_retry() {
  local plist_path="$1"
  local attempt_number
  for attempt_number in 1 2 3 4 5; do
    if (( attempt_number == 5 )); then
      /bin/launchctl bootstrap "$launch_domain" "$plist_path" && return 0
    elif /bin/launchctl bootstrap "$launch_domain" "$plist_path" 2>/dev/null; then
      return 0
    fi
    /bin/sleep "$attempt_number"
  done
  return 1
}

bootstrap_with_retry "$launch_agents_directory/$service_label.plist"
if ! bootstrap_with_retry "$launch_agents_directory/$watchdog_label.plist"; then
  /bin/launchctl bootout "$launch_domain/$service_label" 2>/dev/null || true
  exit 71
fi

for wait_number in {1..20}; do
  identity=$(
    /usr/bin/curl --silent --fail --connect-timeout 1 --max-time 2 \
      "http://127.0.0.1:8787/api/v1" 2>/dev/null
  ) || identity=""
  if [[ "$identity" == *'"name":"Container GUI"'* ]]; then
    print "Container GUI $app_version is managed by launchd at http://127.0.0.1:8787/."
    print "Logs: $log_directory"
    exit 0
  fi
  /bin/sleep 1
done

print -u2 "LaunchAgent was loaded, but the Container GUI identity check did not pass."
print -u2 "Inspect $log_directory/service-error.log."
exit 75
