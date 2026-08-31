#!/bin/zsh

set -u

readonly identity_url="http://127.0.0.1:8787/api/v1"
readonly service_target="gui/$(/usr/bin/id -u)/com.msj.container-gui"
readonly auth_token_file="$HOME/Library/Application Support/ContainerGUI/auth-token"
readonly auth_token="$(/usr/bin/tr -d '\r\n' < "$auth_token_file" 2>/dev/null)"

if ! print -r -- "$auth_token" | /usr/bin/grep -Eq '^[0-9A-Fa-f]{64}$'; then
  print -u2 "Container GUI authentication token is missing or invalid."
  exit 1
fi

for attempt_number in 1 2; do
  response=$(
    print -r -- "user = \"container-gui:$auth_token\"" | \
      /usr/bin/curl \
        --config - \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 2 \
        --max-time 4 \
        "$identity_url" 2>/dev/null
  ) || response=""

  if [[ "$response" == *'"name":"Container GUI"'* ]]; then
    exit 0
  fi

  if (( attempt_number == 1 )); then
    /bin/sleep 2
  fi
done

print -u2 "Container GUI identity probe failed twice; restarting $service_target"
/bin/launchctl kickstart -k "$service_target"
