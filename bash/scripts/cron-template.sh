#!/usr/bin/env bash

## Original https://habr.com/ru/articles/778922/

##
# bash options
##

set -eu -o pipefail

export LC_ALL="C"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

##
# Variables
##

SET_EXECUTION_LOCK="${SET_EXECUTION_LOCK:-}"
MAX_EXECUTION_TIME="${MAX_EXECUTION_TIME:-10}"
START_DELAY_RANGE="${START_DELAY_RANGE:-0-0}"
LOGS="/var/log/$(basename "$0")"
HOSTNAME="${HOSTNAME:-$(hostname -f)}"
REPORT_MAIL="monitoring@example.com"
REPORT_SUBJ="$0 fail on $HOSTNAME"
#ZABBIX_ITEM="example.task.ok"

##
# Execution lock and timeout
##

if [[ -n "$MAX_EXECUTION_TIME" ]]; then
  command="timeout -v -k 60 $MAX_EXECUTION_TIME"
fi

if [[ -n "$SET_EXECUTION_LOCK" ]]; then
  command="flock -E 0 -n $0 ${command:-}"

fi

if [[ -z "${_run_:-}" ]]; then
  sleep "$(shuf -i "$START_DELAY_RANGE" -n 1)"
  export _run_=1
  exec ${command:-} "$0" "$@"
fi

##
# Functions
##

print_logs() {
  cd "$LOGS"

  echo "Trace of $HOSTNAME:$0"
  for log in stderr stdout; do
    if [[ -s "$log" ]]; then
      echo "----- $(basename "$log")"
      tail -n 10000 "$log"
    fi
  done
}

send_to_zabbix() {
  local item="${1:-}"
  local value="${2:-1}"

  zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -s "$HOSTNAME" -k "$item" -o "$value"
}

on_exit() {
  return
}

on_error() {
  print_logs 2>&1 | mail -E -s "$REPORT_SUBJ" "$REPORT_MAIL"
  on_exit

  # Нам не нужно лишнее письмо от crond
  exit 0
}

main() {
  set -x

  "$@"

  if [[ -n "${ZABBIX_ITEM:-}" ]]; then
    send_to_zabbix "${ZABBIX_ITEM:-}" 1
  fi
}

##
# Main
##

trap on_error ERR
trap on_exit EXIT

[[ -d "$LOGS" ]] || mkdir -p "$LOGS"

(main "$@" > "$LOGS/stdout" 2> "$LOGS/stderr")