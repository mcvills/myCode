#!/usr/bin/env bash
# Audit, collect, install, and validate the TLS CA chain used by XNAT XSync.
# Run this script on the XSync SOURCE server. --peer identifies the DESTINATION.

set -Eeuo pipefail
IFS=$'\n\t'

readonly VERSION="1.0.0"
MODE="audit"
DRY_RUN=false
RESTART_TOMCAT=false
PEER_URL=""
EXTRA_CA_FILE=""
JAVA_CACERTS=""
TOMCAT_SERVICE="tomcat.service"
OUTPUT_BASE="/var/lib/xnat-xsync-tls"
TRUSTSTORE_PASSWORD="${XNAT_TRUSTSTORE_PASSWORD:-changeit}"
WORK_DIR=""
PEER_HOST=""
PEER_PORT="443"
CHAIN_FILE=""
LEAF_FILE=""
CA_DIR=""
REPORT_FILE=""

info() { printf '\033[1;34m[INFO]\033[0m    %s\n' "$*"; }
ok()   { printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m    %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[ERROR]\033[0m   %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
XNAT XSync TLS Trust Manager 1.0.0

Run on the XSync SOURCE server; --peer is the destination XNAT URL.

Usage:
  xnat-xsync-tls-trust.sh --peer https://xnat-destination.example.org [options]

Options:
  --mode audit|install     audit is read-only (default); install updates trust
  --ca-file FILE          trusted root/intermediate PEM supplied out-of-band
  --java-cacerts FILE     Java truststore used by Tomcat/XNAT
  --tomcat-service NAME   service to restart (default: tomcat.service)
  --restart-tomcat        restart Tomcat after a successful trust update
  --output-dir DIR        evidence/output parent (default: /var/lib/xnat-xsync-tls)
  --dry-run               preview install actions without changing trust
  -h, --help              show help

Environment:
  XNAT_TRUSTSTORE_PASSWORD  Java truststore password (default: changeit)

Examples:
  ./xnat-xsync-tls-trust.sh --peer https://ui-xnat.example.org
  sudo ./xnat-xsync-tls-trust.sh --peer https://ui-xnat.example.org \
    --mode install --ca-file /secure/emsign-root.pem --restart-tomcat
EOF
}

while (($#)); do
  case "$1" in
    --peer) PEER_URL=${2:?Missing value for --peer}; shift 2 ;;
    --mode) MODE=${2:?Missing value for --mode}; shift 2 ;;
    --ca-file) EXTRA_CA_FILE=${2:?Missing value for --ca-file}; shift 2 ;;
    --java-cacerts) JAVA_CACERTS=${2:?Missing value for --java-cacerts}; shift 2 ;;
    --tomcat-service) TOMCAT_SERVICE=${2:?Missing value for --tomcat-service}; shift 2 ;;
    --restart-tomcat) RESTART_TOMCAT=true; shift ;;
    --output-dir) OUTPUT_BASE=${2:?Missing value for --output-dir}; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ "$MODE" == "audit" || "$MODE" == "install" ]] || fail "--mode must be audit or install."
[[ -n "$PEER_URL" ]] || { usage >&2; fail "--peer is required."; }
[[ "$PEER_URL" =~ ^https://[^/]+(:[0-9]+)?(/.*)?$ ]] || fail "--peer must be an HTTPS URL."
[[ -z "$EXTRA_CA_FILE" || -r "$EXTRA_CA_FILE" ]] || fail "Cannot read --ca-file: $EXTRA_CA_FILE"

for command_name in openssl curl awk sed date sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done

authority=${PEER_URL#https://}
authority=${authority%%/*}
if [[ "$authority" == \[*\]*:* ]]; then
  PEER_HOST=${authority%%]:*}; PEER_HOST=${PEER_HOST#[}
  PEER_PORT=${authority##*:}
elif [[ "$authority" == *:* ]]; then
  PEER_HOST=${authority%:*}; PEER_PORT=${authority##*:}
else
  PEER_HOST=$authority
fi
[[ "$PEER_PORT" =~ ^[0-9]+$ ]] || fail "Invalid peer port: $PEER_PORT"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
if ! mkdir -p -- "$OUTPUT_BASE" 2>/dev/null; then
  if [[ "$MODE" == "audit" ]]; then
    OUTPUT_BASE=${TMPDIR:-/tmp}/xnat-xsync-tls
    mkdir -p -- "$OUTPUT_BASE"
    warn "Cannot write the requested output parent; using $OUTPUT_BASE"
  else
    fail "Cannot create output directory: $OUTPUT_BASE"
  fi
fi
WORK_DIR="$OUTPUT_BASE/${PEER_HOST}_${PEER_PORT}_$timestamp"
CHAIN_FILE="$WORK_DIR/presented-chain.pem"
LEAF_FILE="$WORK_DIR/leaf.pem"
CA_DIR="$WORK_DIR/ca-certificates"
REPORT_FILE="$WORK_DIR/report.txt"
mkdir -p -- "$CA_DIR"
chmod 0700 "$WORK_DIR" "$CA_DIR"

exec > >(tee -a "$REPORT_FILE") 2>&1

printf '\nXNAT XSync TLS Trust Manager v%s\n' "$VERSION"
printf 'Run location : XSync source server\n'
printf 'Peer target  : %s\n' "$PEER_URL"
printf 'Mode         : %s%s\n\n' "$MODE" "$($DRY_RUN && printf ' (dry-run)' || true)"

info "Testing peer with curl using the current OS trust store."
before_code=$(curl --silent --show-error --location --output /dev/null \
  --connect-timeout 10 --max-time 30 --write-out '%{http_code}' "$PEER_URL" 2>"$WORK_DIR/curl-before.err") || before_rc=$?
before_rc=${before_rc:-0}
if ((before_rc == 0)); then
  ok "curl TLS validation succeeded (HTTP ${before_code:-unknown})."
else
  warn "curl failed before trust changes (exit $before_rc): $(<"$WORK_DIR/curl-before.err")"
fi

info "Collecting the certificate chain presented by $PEER_HOST:$PEER_PORT."
openssl s_client -showcerts -servername "$PEER_HOST" \
  -connect "$PEER_HOST:$PEER_PORT" </dev/null \
  >"$WORK_DIR/s_client.txt" 2>"$WORK_DIR/s_client.err" || true

awk '
  /-----BEGIN CERTIFICATE-----/ {inside=1}
  inside {print}
  /-----END CERTIFICATE-----/ {inside=0}
' "$WORK_DIR/s_client.txt" >"$CHAIN_FILE"
grep -q -- '-----BEGIN CERTIFICATE-----' "$CHAIN_FILE" || fail "The peer did not present a certificate. See $WORK_DIR/s_client.err"

awk -v out="$WORK_DIR/cert-" '
  /-----BEGIN CERTIFICATE-----/ {n++; file=sprintf("%s%03d.pem", out, n)}
  n {print > file}
  /-----END CERTIFICATE-----/ {close(file)}
' "$CHAIN_FILE"

mapfile -t presented_certs < <(find "$WORK_DIR" -maxdepth 1 -type f -name 'cert-*.pem' | sort)
cp -- "${presented_certs[0]}" "$LEAF_FILE"
openssl x509 -in "$LEAF_FILE" -noout -checkhost "$PEER_HOST" >/dev/null \
  && ok "Leaf certificate matches hostname $PEER_HOST." \
  || fail "Leaf certificate does not match hostname $PEER_HOST."

root_present=false
ca_count=0
printf '\nPresented certificates:\n'
for cert in "${presented_certs[@]}"; do
  subject=$(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
  issuer=$(openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 | sed 's/^issuer=//')
  fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | sed 's/.*=//;s/://g')
  dates=$(openssl x509 -in "$cert" -noout -dates | tr '\n' ' ')
  printf '  %s\n    Subject: %s\n    Issuer : %s\n    SHA256 : %s\n    Dates  : %s\n' \
    "${cert##*/}" "$subject" "$issuer" "$fingerprint" "$dates"
  openssl x509 -in "$cert" -noout -checkend 0 >/dev/null || fail "Expired certificate: $subject"
  if [[ "$cert" != "${presented_certs[0]}" ]]; then
    ca_count=$((ca_count + 1))
    cp -- "$cert" "$CA_DIR/presented-$ca_count.pem"
    [[ "$subject" == "$issuer" ]] && root_present=true
  fi
done

if [[ -n "$EXTRA_CA_FILE" ]]; then
  info "Splitting administrator-supplied CA file: $EXTRA_CA_FILE"
  awk -v out="$CA_DIR/supplied-" '
    /-----BEGIN CERTIFICATE-----/ {n++; file=sprintf("%s%03d.pem", out, n)}
    n {print > file}
    /-----END CERTIFICATE-----/ {close(file)}
  ' "$EXTRA_CA_FILE"
fi

mapfile -t ca_candidates < <(find "$CA_DIR" -maxdepth 1 -type f -name '*.pem' | sort)
for cert in "${ca_candidates[@]}"; do
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || fail "Invalid PEM certificate: $cert"
  is_ca=$(openssl x509 -in "$cert" -noout -text | sed -n '/Basic Constraints/{n;p;}')
  [[ "$is_ca" == *"CA:TRUE"* ]] || fail "Refusing non-CA certificate as trust anchor: $cert"
  subject=$(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
  issuer=$(openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 | sed 's/^issuer=//')
  [[ "$subject" == "$issuer" ]] && root_present=true
done

if $root_present; then
  ok "A self-signed root CA is available in the collected/supplied CA set."
else
  warn "No self-signed root CA was presented or supplied. TLS servers normally omit the root."
  warn "For a private/untrusted PKI, obtain the root CA securely and rerun with --ca-file."
fi

if [[ "$MODE" == "audit" ]]; then
  ok "Audit completed without changing system or Java trust."
  printf 'Evidence directory: %s\n' "$WORK_DIR"
  exit 0
fi

((${#ca_candidates[@]} > 0)) || fail "No CA certificates are available to install."
((EUID == 0)) || fail "Install mode must run as root."

if [[ -z "$JAVA_CACERTS" ]]; then
  java_bin=""
  if command -v systemctl >/dev/null 2>&1; then
    tomcat_pid=$(systemctl show --property MainPID --value "$TOMCAT_SERVICE" 2>/dev/null || true)
    if [[ "$tomcat_pid" =~ ^[1-9][0-9]*$ && -r "/proc/$tomcat_pid/cmdline" ]]; then
      configured_store=$(tr '\0' '\n' <"/proc/$tomcat_pid/cmdline" \
        | sed -n 's/^-Djavax\.net\.ssl\.trustStore=//p' | head -n 1)
      if [[ -n "$configured_store" ]]; then
        JAVA_CACERTS=$configured_store
        info "Detected Tomcat's explicit javax.net.ssl.trustStore setting."
      else
        java_bin=$(readlink -f "/proc/$tomcat_pid/exe" 2>/dev/null || true)
        [[ -n "$java_bin" ]] && info "Detected the Java runtime used by $TOMCAT_SERVICE."
      fi
    fi
  fi
  [[ -n "$java_bin" ]] || java_bin=$(readlink -f "$(command -v java || true)" 2>/dev/null || true)
  candidates=(
    "${java_bin%/bin/java}/lib/security/cacerts"
    "/etc/ssl/certs/java/cacerts"
  )
  if [[ -z "$JAVA_CACERTS" ]]; then
    for candidate in "${candidates[@]}"; do
      [[ -f "$candidate" ]] && { JAVA_CACERTS=$candidate; break; }
    done
  fi
fi
[[ -n "$JAVA_CACERTS" && -f "$JAVA_CACERTS" ]] || fail "Java cacerts not found; specify --java-cacerts."
command -v keytool >/dev/null 2>&1 || fail "keytool is required for install mode."
command -v update-ca-certificates >/dev/null 2>&1 || fail "update-ca-certificates is required on Debian."

info "Java truststore: $JAVA_CACERTS"
backup="$JAVA_CACERTS.xsync-backup-$timestamp"
if $DRY_RUN; then
  info "DRY RUN: would back up Java truststore to $backup"
else
  cp -a -- "$JAVA_CACERTS" "$backup"
  chmod --reference="$JAVA_CACERTS" "$backup"
  ok "Java truststore backup created: $backup"
fi

installed=0
for cert in "${ca_candidates[@]}"; do
  fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | sed 's/.*=//;s/://g')
  alias="xnat-xsync-${PEER_HOST//[^A-Za-z0-9._-]/_}-${fingerprint:0:16}"
  os_cert="/usr/local/share/ca-certificates/$alias.crt"

  if $DRY_RUN; then
    info "DRY RUN: would install $cert as $os_cert and Java alias $alias"
    continue
  fi

  cp -- "$cert" "$os_cert"
  chmod 0644 "$os_cert"
  if keytool -list -keystore "$JAVA_CACERTS" -storepass "$TRUSTSTORE_PASSWORD" \
      -alias "$alias" >/dev/null 2>&1; then
    info "Java alias already exists: $alias"
  else
    keytool -importcert -noprompt -trustcacerts -keystore "$JAVA_CACERTS" \
      -storepass "$TRUSTSTORE_PASSWORD" -alias "$alias" -file "$cert" >/dev/null
    ok "Imported Java trust alias: $alias"
    installed=$((installed + 1))
  fi
done

if $DRY_RUN; then
  ok "Dry run completed; no truststore, OS trust, or service changes were made."
  printf 'Evidence directory: %s\n' "$WORK_DIR"
  exit 0
fi

update-ca-certificates
ok "Debian OS CA trust updated."

info "Validating the destination with curl after trust installation."
after_code=$(curl --silent --show-error --location --output /dev/null \
  --connect-timeout 10 --max-time 30 --write-out '%{http_code}' "$PEER_URL") \
  || fail "curl still cannot validate/connect to $PEER_URL"
ok "curl TLS validation succeeded after installation (HTTP ${after_code:-unknown})."

if $RESTART_TOMCAT; then
  systemctl restart "$TOMCAT_SERVICE"
  systemctl is-active --quiet "$TOMCAT_SERVICE" || fail "$TOMCAT_SERVICE did not become active."
  ok "$TOMCAT_SERVICE restarted and is active."
else
  warn "Tomcat was not restarted. Restart $TOMCAT_SERVICE during the approved window so XSync reloads Java trust."
fi

ok "TLS trust workflow completed; $installed new Java alias(es) imported."
printf 'Evidence directory: %s\n' "$WORK_DIR"
printf 'Java rollback copy: %s\n' "$backup"
