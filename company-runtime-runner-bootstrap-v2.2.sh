#!/usr/bin/env bash
# Production runner bootstrap V2.2. Run as root in a child shell; never source it.
set -Eeuo pipefail

RUNNER_USER="${RUNNER_USER:-company-ai-runner}"
RUNNER_NAME="${RUNNER_NAME:-company-ai-runtime-v1}"
RUNNER_ROOT="${RUNNER_ROOT:-/opt/actions-runner}"
GITHUB_ORG_URL="${GITHUB_ORG_URL:-https://github.com/yuque-ai}"
RUNNER_GROUP="${RUNNER_GROUP:-company-runtime-production}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LOG="${RUNNER_LOG:-/dev/shm/company-runner-register-safe.log}"
RUNNER_TEST_MODE="${RUNNER_TEST_MODE:-0}"
CURL_BIN="${CURL_BIN:-curl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"

STATE=""
SERVICE_UNIT=""

log() { printf '%s\n' "$1" | tee -a "$RUNNER_LOG"; }
redact() { sed -E 's/(token|authorization|credentials|private.?key|github.?app)[=:[:space:]]+[^[:space:]]+/\1=[REDACTED]/Ig'; }
safe_tail() { local lines; lines="$(tail -n 20 "$RUNNER_LOG" | redact)"; log "SAFE_LAST20_BEGIN"; printf '%s\n' "$lines" | tee -a "$RUNNER_LOG"; log "SAFE_LAST20_END"; }
fail() { log "$1=FAIL"; [ -n "${2:-}" ] && log "${1}_ERROR=$2"; safe_tail; log "FINAL=FAIL"; exit "${3:-1}"; }
capture() { "$@" 2>&1 | redact | tee -a "$RUNNER_LOG"; return "${PIPESTATUS[0]}"; }

init_log() {
  umask 077
  : > "$RUNNER_LOG"
  chmod 600 "$RUNNER_LOG"
}

as_runner() {
  if [ "$RUNNER_TEST_MODE" = "1" ]; then "$@"; else runuser -u "$RUNNER_USER" -- "$@"; fi
}

service_unit() {
  "$SYSTEMCTL_BIN" list-unit-files --type=service --no-legend 'actions.runner*' 2>/dev/null \
    | awk 'NR==1 {print $1}'
}

is_active() { [ -n "$SERVICE_UNIT" ] && "$SYSTEMCTL_BIN" is-active --quiet "$SERVICE_UNIT"; }
is_enabled() { [ -n "$SERVICE_UNIT" ] && "$SYSTEMCTL_BIN" is-enabled --quiet "$SERVICE_UNIT"; }

preflight() {
  [ "$RUNNER_USER" = "company-ai-runner" ] || fail BOOTSTRAP_VARS runner_user 64
  [ "$RUNNER_NAME" = "company-ai-runtime-v1" ] || fail BOOTSTRAP_VARS runner_name 64
  [ "$GITHUB_ORG_URL" = "https://github.com/yuque-ai" ] || fail BOOTSTRAP_VARS github_org 64
  [ "$RUNNER_GROUP" = "company-runtime-production" ] || fail BOOTSTRAP_VARS runner_group 64
  log "BOOTSTRAP_VARS=PASS"
  command -v "$CURL_BIN" >/dev/null || fail PRECHECK_TOOLS curl 65
  command -v "$PYTHON_BIN" >/dev/null || fail PRECHECK_TOOLS python 65
  command -v tar >/dev/null || fail PRECHECK_TOOLS tar 65
  command -v sha256sum >/dev/null || fail PRECHECK_TOOLS sha256sum 65
  command -v "$SYSTEMCTL_BIN" >/dev/null || fail PRECHECK_TOOLS systemctl 65
  "$CURL_BIN" --fail --silent --show-error --connect-timeout 10 --max-time 20 --output /dev/null https://github.com/ || fail PRECHECK_NETWORK github 65
  "$CURL_BIN" --fail --silent --show-error --connect-timeout 10 --max-time 20 --output /dev/null https://api.github.com/ || fail PRECHECK_NETWORK github_api 65
  log "PRECHECK_TOOLS=PASS"
  log "PRECHECK_NETWORK=PASS"
}

ensure_user_and_root() {
  if ! getent passwd "$RUNNER_USER" >/dev/null 2>&1; then
    [ "$RUNNER_TEST_MODE" = "1" ] || useradd --create-home --shell /bin/bash "$RUNNER_USER"
  fi
  getent passwd "$RUNNER_USER" >/dev/null 2>&1 || fail PRECHECK_USER missing_user 66
  log "PRECHECK_USER=PASS"
  if [ "$RUNNER_TEST_MODE" = "1" ]; then mkdir -p "$RUNNER_ROOT"; chmod 700 "$RUNNER_ROOT"; else install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0700 "$RUNNER_ROOT"; fi
}

has_extracted_runner() {
  [ -x "$RUNNER_ROOT/config.sh" ] && [ -x "$RUNNER_ROOT/run.sh" ] &&
    [ -d "$RUNNER_ROOT/bin" ] && [ -d "$RUNNER_ROOT/externals" ]
}

has_configured_runner() {
  has_extracted_runner && [ -x "$RUNNER_ROOT/svc.sh" ] &&
    [ -f "$RUNNER_ROOT/.runner" ] && [ -f "$RUNNER_ROOT/.credentials" ]
}

detect_state() {
  SERVICE_UNIT="$(service_unit || true)"
  if [ ! -e "$RUNNER_ROOT" ] || [ -z "$(find "$RUNNER_ROOT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then echo STATE_A_CLEAN; return; fi
  if ! has_extracted_runner && [ -z "$(find "$RUNNER_ROOT" -mindepth 1 -maxdepth 1 -type f ! -name 'actions-runner-linux-x64-*.tar.gz' -print -quit)" ] && [ "$(find "$RUNNER_ROOT" -mindepth 1 -maxdepth 1 -type f -name 'actions-runner-linux-x64-*.tar.gz' | wc -l)" -eq 1 ]; then echo STATE_B_DOWNLOADED_ONLY; return; fi
  if has_extracted_runner && [ ! -e "$RUNNER_ROOT/.runner" ] && [ ! -e "$RUNNER_ROOT/.credentials" ] && [ -z "$SERVICE_UNIT" ]; then echo STATE_C_EXTRACTED_NOT_REGISTERED; return; fi
  if has_configured_runner; then
    [ -n "$SERVICE_UNIT" ] || { echo STATE_D_CONFIGURED_NOT_SERVICE; return; }
    is_active && is_enabled && { echo STATE_F_ONLINE; return; }
    echo STATE_E_SERVICE_OFFLINE; return
  fi
  echo STATE_UNKNOWN
}

release_metadata() {
  local json
  json="$("$CURL_BIN" --fail --silent --show-error -H 'Accept: application/vnd.github+json' -H 'User-Agent: company-runtime-runner-bootstrap' "${RUNNER_RELEASE_API_URL:-https://api.github.com/repos/actions/runner/releases/latest}")" || return 1
  printf '%s' "$json" | "$PYTHON_BIN" -c '
import json, sys
d=json.load(sys.stdin)
a=next(x for x in d["assets"] if x["name"].startswith("actions-runner-linux-x64-") and x["name"].endswith(".tar.gz"))
digest=a.get("digest", "")
assert digest.startswith("sha256:") and len(digest)==71
print(a["browser_download_url"]); print(a["name"]); print(digest[7:])
'
}

download_and_extract() {
  mapfile -t meta < <(release_metadata) || fail DOWNLOAD release_metadata 67
  [ "${#meta[@]}" -eq 3 ] || fail DOWNLOAD malformed_metadata 67
  local url="${meta[0]}" expected="${meta[2]}" archive="$RUNNER_ROOT/${meta[1]}"
  as_runner "$CURL_BIN" --fail --silent --show-error --location "$url" -o "$archive" || fail DOWNLOAD curl 67
  printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --status || fail SHA256 asset_mismatch 68
  as_runner tar -xzf "$archive" -C "$RUNNER_ROOT" || fail EXTRACT tar 69
  rm -f -- "$archive"
  has_extracted_runner || fail EXTRACT missing_runner_files 69
}

register_once() {
  log "READY_FOR_REGISTRATION=PASS"
  # GitHub's official unattended contract requires a registration token passed to config.sh.
  # Read once from the TTY only after the READY gate; it is neither persisted nor logged.
  local rc
  local TOKEN=""
  trap 'unset TOKEN' EXIT
  printf 'Registration token: ' >&2
  if ! IFS= read -r -s TOKEN; then
    printf '\n' >&2
    fail REGISTRATION token_read 70
  fi
  printf '\n' >&2
  [ -n "$TOKEN" ] || fail REGISTRATION token_missing 70
  run_config() {
    (
      cd "$RUNNER_ROOT" &&
      as_runner ./config.sh --url "$GITHUB_ORG_URL" --token "$TOKEN" \
        --name "$RUNNER_NAME" --runnergroup "$RUNNER_GROUP" \
        --work "$RUNNER_WORKDIR" --unattended --replace
    )
  }
  if capture run_config; then rc=0; else rc=$?; fi
  unset TOKEN
  log "TOKEN_CLEARED=PASS"
  [ "$rc" -eq 0 ] || fail REGISTRATION "exit_$rc" 70
  [ -f "$RUNNER_ROOT/.runner" ] && [ -f "$RUNNER_ROOT/.credentials" ] || fail REGISTRATION missing_runner_files 70
  [ -x "$RUNNER_ROOT/svc.sh" ] || fail REGISTRATION svc_missing 70
  log "REGISTRATION=PASS"
}

install_and_start_service() {
  local rc
  [ -x "$RUNNER_ROOT/svc.sh" ] || fail SERVICE_INSTALL svc_missing 71
  if capture "$RUNNER_ROOT/svc.sh" install "$RUNNER_USER"; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] || fail SERVICE_INSTALL "exit_$rc" 71
  SERVICE_UNIT="$(service_unit || true)"; [ -n "$SERVICE_UNIT" ] || fail SERVICE_INSTALL unit_missing 71
  capture "$SYSTEMCTL_BIN" enable "$SERVICE_UNIT" || fail SERVICE_START enable 72
  if capture "$RUNNER_ROOT/svc.sh" start; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] || fail SERVICE_START "exit_$rc" 72
  if ! is_active || ! is_enabled; then fail SERVICE_START inactive_or_disabled 72; fi
  log "SERVICE_INSTALL=PASS"; log "SERVICE_START=PASS"
}

start_service() {
  capture "$SYSTEMCTL_BIN" enable "$SERVICE_UNIT" || fail SERVICE_START enable 72
  local rc
  if capture "$RUNNER_ROOT/svc.sh" start; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] || fail SERVICE_START "exit_$rc" 72
  if ! is_active || ! is_enabled; then fail SERVICE_START inactive_or_disabled 72; fi
  log "SERVICE_START=PASS"
}

main() {
  init_log; preflight; ensure_user_and_root
  STATE="$(detect_state)"; SERVICE_UNIT="$(service_unit || true)"; log "STATE=$STATE"
  [ "$STATE" != STATE_UNKNOWN ] || fail PRECHECK_STATE unknown_layout 78
  log "PRECHECK_FILES=PASS"; log "PRECHECK_STATE=PASS"
  case "$STATE" in
    STATE_A_CLEAN) download_and_extract; register_once; install_and_start_service ;;
    STATE_B_DOWNLOADED_ONLY) rm -f -- "$RUNNER_ROOT"/actions-runner-linux-x64-*.tar.gz; download_and_extract; register_once; install_and_start_service ;;
    STATE_C_EXTRACTED_NOT_REGISTERED) register_once; install_and_start_service ;;
    STATE_D_CONFIGURED_NOT_SERVICE) log "REGISTRATION=PASS"; install_and_start_service ;;
    STATE_E_SERVICE_OFFLINE) log "REGISTRATION=PASS"; log "SERVICE_INSTALL=PASS"; start_service ;;
    STATE_F_ONLINE) log "REGISTRATION=PASS"; log "SERVICE_INSTALL=PASS"; log "SERVICE_START=PASS"; log "NOOP=PASS" ;;
  esac
  STATE="$(detect_state)"; [ "$STATE" = STATE_F_ONLINE ] || fail READBACK "$STATE" 79
  log "RUNNER_FILES=PASS"; log "FINAL=PASS"
}

main "$@"
