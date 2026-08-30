#!/bin/zsh

set -u

readonly identity_url="http://127.0.0.1:8787/api/v1"
readonly service_target="gui/$(/usr/bin/id -u)/com.msj.container-gui"

for attempt_number in 1 2; do
  response=$(
    /usr/bin/curl \
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
