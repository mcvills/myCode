#!/usr/bin/env bash
# XNAT/XSync pre-work readiness audit
# Read-only: gathers host and XNAT configuration metadata and writes an HTML report.

set -uo pipefail
IFS=$'\n\t'

VERSION="1.0.4"
OUTPUT="./xnat-xsync-prework-$(hostname -s 2>/dev/null || echo host)-$(date -u +%Y%m%dT%H%M%SZ).html"
PEER_FQDN=""
PEER_IP=""
LOCAL_URL=""
XNAT_HOME_OVERRIDE=""
TOMCAT_SERVICE_OVERRIDE=""
SERVICE_ACCOUNT=""
OPEN_REPORT=false

usage() {
  cat <<'EOF'
Usage: sudo ./xnat-xsync-prework-audit.sh [options]

Options:
  --output FILE             HTML report destination
  --local-url URL           Local public XNAT URL, e.g. https://xnat-a.example.org
  --peer-fqdn HOSTNAME      Remote XNAT FQDN for DNS/TLS/HTTPS readiness tests
  --peer-ip ADDRESS         Expected remote IP for comparison and route testing
  --xnat-home DIRECTORY     Override automatic XNAT_HOME discovery
  --tomcat-service NAME     Override automatic Tomcat systemd service discovery
  --service-account NAME    Expected local inbound XSync account (name only)
  --open                    Open report locally when a graphical opener is available
  -h, --help                Show this help

The script is read-only. It never requests, stores, or displays passwords.
Run once on each XNAT server. Peer tests are marked DEFERRED until peer details
and Layer 1/3 connectivity are available.
EOF
}

while (($#)); do
  case "$1" in
    --output) OUTPUT=${2:?Missing value for --output}; shift 2 ;;
    --local-url) LOCAL_URL=${2:?Missing value for --local-url}; shift 2 ;;
    --peer-fqdn) PEER_FQDN=${2:?Missing value for --peer-fqdn}; shift 2 ;;
    --peer-ip) PEER_IP=${2:?Missing value for --peer-ip}; shift 2 ;;
    --xnat-home) XNAT_HOME_OVERRIDE=${2:?Missing value for --xnat-home}; shift 2 ;;
    --tomcat-service) TOMCAT_SERVICE_OVERRIDE=${2:?Missing value for --tomcat-service}; shift 2 ;;
    --service-account) SERVICE_ACCOUNT=${2:?Missing value for --service-account}; shift 2 ;;
    --open) OPEN_REPORT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in "$LOCAL_URL" "$PEER_FQDN" "$PEER_IP" "$SERVICE_ACCOUNT"; do
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    printf 'Invalid newline in argument.\n' >&2
    exit 2
  fi
done

TMP_DIR=$(mktemp -d -t xnat-xsync-audit.XXXXXX)
BODY_FILE="$TMP_DIR/body.html"
CHECK_FILE="$TMP_DIR/checks.tsv"
trap 'rm -rf -- "$TMP_DIR"' EXIT
: >"$BODY_FILE"
: >"$CHECK_FILE"

html() {
  local text=${1-}
  text=${text//&/&amp;}
  text=${text//</&lt;}
  text=${text//>/&gt;}
  text=${text//\"/&quot;}
  text=${text//\'/&#39;}
  printf '%s' "$text"
}

clean() {
  local text=${1-}
  text=${text//$'\r'/}
  [[ -n "$text" ]] && printf '%s' "$text" || printf 'Not detected'
}

run() {
  timeout 12s "$@" 2>&1 || true
}

status_class() {
  case "$1" in
    PASS) printf 'pass' ;; WARN) printf 'warn' ;; FAIL) printf 'fail' ;;
    DEFERRED) printf 'deferred' ;; INFO|*) printf 'info' ;;
  esac
}

add_section() {
  printf '<section><h2>%s</h2><div class="table-wrap"><table><tbody>\n' "$(html "$1")" >>"$BODY_FILE"
}

end_section() {
  printf '</tbody></table></div></section>\n' >>"$BODY_FILE"
}

add_row() {
  local label=$1 value=${2-} state=${3:-INFO} note=${4-}
  local cls
  cls=$(status_class "$state")
  printf '<tr><th>%s</th><td><div class="value">%s</div>' "$(html "$label")" "$(html "$(clean "$value")")" >>"$BODY_FILE"
  [[ -n "$note" ]] && printf '<div class="note">%s</div>' "$(html "$note")" >>"$BODY_FILE"
  printf '</td><td class="state"><span class="badge %s">%s</span></td></tr>\n' "$cls" "$(html "$state")" >>"$BODY_FILE"
  printf '%s\t%s\n' "$state" "${label//$'\t'/ }" >>"$CHECK_FILE"
}

add_pre_row() {
  local label=$1 value=${2-} state=${3:-INFO} note=${4-}
  local cls
  cls=$(status_class "$state")
  printf '<tr><th>%s</th><td><pre>%s</pre>' "$(html "$label")" "$(html "$(clean "$value")")" >>"$BODY_FILE"
  [[ -n "$note" ]] && printf '<div class="note">%s</div>' "$(html "$note")" >>"$BODY_FILE"
  printf '</td><td class="state"><span class="badge %s">%s</span></td></tr>\n' "$cls" "$(html "$state")" >>"$BODY_FILE"
  printf '%s\t%s\n' "$state" "${label//$'\t'/ }" >>"$CHECK_FILE"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

prefix_to_mask() {
  local prefix=${1-} mask="" octet bits i
  [[ "$prefix" =~ ^[0-9]+$ ]] && ((prefix >= 0 && prefix <= 32)) || return 0
  for i in 1 2 3 4; do
    bits=$((prefix >= 8 ? 8 : prefix))
    octet=$((bits == 0 ? 0 : 256 - (1 << (8 - bits))))
    mask+="${mask:+.}$octet"
    prefix=$((prefix > 8 ? prefix - 8 : 0))
  done
  printf '%s' "$mask"
}

detect_xnat_home() {
  if [[ -n "$XNAT_HOME_OVERRIDE" ]]; then printf '%s' "$XNAT_HOME_OVERRIDE"; return; fi
  local candidate=""
  candidate=$(ps -eo args 2>/dev/null | sed -n 's/.*-Dxnat.home=\([^ ]*\).*/\1/p' | head -n1)
  if [[ -n "$candidate" ]]; then printf '%s' "$candidate"; return; fi
  for candidate in /data/xnat /opt/xnat /srv/xnat /var/lib/xnat /xnat; do
    [[ -d "$candidate" ]] && { printf '%s' "$candidate"; return; }
  done
  printf ''
}

detect_tomcat_service() {
  if [[ -n "$TOMCAT_SERVICE_OVERRIDE" ]]; then printf '%s' "$TOMCAT_SERVICE_OVERRIDE"; return; fi
  if command_exists systemctl; then
    systemctl list-unit-files --type=service --no-legend 2>/dev/null \
      | awk '$1 ~ /^tomcat.*\.service$/ {sub(/\.service$/, "", $1); print $1; exit}'
  fi
}

HOST_FQDN=$(hostname -f 2>/dev/null || hostname)
HOST_SHORT=$(hostname -s 2>/dev/null || hostname)
GENERATED=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
XNAT_HOME=$(detect_xnat_home)
TOMCAT_SERVICE=$(detect_tomcat_service)

# Host identity
add_section "Host identity and operating system"
OS_NAME=$(awk -F= '$1=="PRETTY_NAME" {gsub(/^"|"$/, "", $2); print $2}' /etc/os-release 2>/dev/null)
add_row "Report version" "$VERSION"
add_row "Generated" "$GENERATED"
add_row "Hostname" "$HOST_SHORT"
add_row "FQDN" "$HOST_FQDN" "$([[ "$HOST_FQDN" == *.* ]] && echo PASS || echo WARN)" "A canonical FQDN is recommended for TLS and XSync."
add_row "Operating system" "$OS_NAME"
add_row "Kernel" "$(uname -srmo 2>/dev/null)"
add_row "Virtualization" "$(run systemd-detect-virt)"
add_row "Audit privileges" "$([[ $EUID -eq 0 ]] && echo 'Running as root; full local visibility' || echo 'Non-root; firewall, certificates, and service details may be incomplete')" "$([[ $EUID -eq 0 ]] && echo PASS || echo WARN)"
end_section

# Network
add_section "Network configuration"
DEFAULT_ROUTE=$(ip -4 route show default 2>/dev/null | head -n1)
ACTIVE_IF=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' <<<"$DEFAULT_ROUTE")
GATEWAY=$(awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}' <<<"$DEFAULT_ROUTE")
IP_CIDR=""
SUBNET_MASK=""
if [[ -n "$ACTIVE_IF" ]]; then
  IP_CIDR=$(ip -o -4 addr show dev "$ACTIVE_IF" scope global 2>/dev/null | awk '{print $4}' | paste -sd ', ' -)
  PRIMARY_PREFIX=$(ip -o -4 addr show dev "$ACTIVE_IF" scope global 2>/dev/null | awk 'NR==1 {split($4,a,"/"); print a[2]}')
  SUBNET_MASK=$(prefix_to_mask "$PRIMARY_PREFIX")
fi
add_row "Active interface" "$ACTIVE_IF" "$([[ -n "$ACTIVE_IF" ]] && echo PASS || echo FAIL)"
add_row "IPv4 address/prefix" "$IP_CIDR" "$([[ -n "$IP_CIDR" ]] && echo PASS || echo FAIL)" "CIDR prefix is the subnet-mask representation."
add_row "Subnet mask" "$SUBNET_MASK" "$([[ -n "$SUBNET_MASK" ]] && echo PASS || echo WARN)"
add_row "Default gateway" "$GATEWAY" "$([[ -n "$GATEWAY" ]] && echo PASS || echo WARN)"
add_pre_row "Default route" "$DEFAULT_ROUTE"
add_pre_row "All active addresses" "$(ip -br address show up 2>/dev/null)"
add_pre_row "Routing table" "$(ip -4 route show 2>/dev/null)"
add_pre_row "DNS configuration" "$(run resolvectl status)"
end_section

# Domain/realm membership
add_section "Domain and realm membership"
if command_exists realm; then
  REALM_LIST=$(run realm list)
  REALM_NAMES=$(awk -F': ' '/^[[:space:]]*realm-name:/ {gsub(/^[[:space:]]+/, "", $2); print $2}' <<<"$REALM_LIST")
  if [[ -n "$REALM_NAMES" ]]; then
    REALM_STATE=PASS
  elif [[ -n "$REALM_LIST" ]]; then
    REALM_STATE=WARN
  else
    REALM_STATE=INFO
  fi
  add_pre_row "Realm name" "$REALM_NAMES" "$REALM_STATE" "Collected from realm list entries named realm-name."
  add_pre_row "Complete realm configuration" "$REALM_LIST" INFO
else
  add_row "Realm membership" "The realm command is not installed" INFO "This is expected when the XNAT host is not joined to Active Directory or FreeIPA."
fi
add_row "DNS search domain" "$(awk '$1=="search" {for(i=2;i<=NF;i++) printf "%s%s", (i==2?"":" "), $i; print ""}' /etc/resolv.conf 2>/dev/null | head -n1)" INFO
end_section

# Time
add_section "Time synchronization"
TIME_STATUS=$(run timedatectl)
TIME_SYNC=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
add_pre_row "timedatectl" "$TIME_STATUS" "$([[ "$TIME_SYNC" == yes ]] && echo PASS || echo WARN)" "Accurate clocks are required for TLS and reliable audit timestamps."
end_section
# Runtime/services
add_section "XNAT application runtime"
add_row "Detected XNAT_HOME" "$XNAT_HOME" "$([[ -n "$XNAT_HOME" && -d "$XNAT_HOME" ]] && echo PASS || echo WARN)" "Use --xnat-home if automatic discovery is incorrect."
add_row "Tomcat systemd service" "$TOMCAT_SERVICE" "$([[ -n "$TOMCAT_SERVICE" ]] && echo PASS || echo WARN)" "Use --tomcat-service if automatic discovery is incorrect."
if [[ -n "$TOMCAT_SERVICE" ]]; then
  TOMCAT_ACTIVE=$(systemctl is-active "$TOMCAT_SERVICE" 2>/dev/null || true)
  TOMCAT_ENABLED=$(systemctl is-enabled "$TOMCAT_SERVICE" 2>/dev/null || true)
else
  TOMCAT_ACTIVE="not detected"; TOMCAT_ENABLED="not detected"
fi
add_row "Tomcat state" "$TOMCAT_ACTIVE" "$([[ "$TOMCAT_ACTIVE" == active ]] && echo PASS || echo WARN)"
add_row "Tomcat boot state" "$TOMCAT_ENABLED" "$([[ "$TOMCAT_ENABLED" == enabled ]] && echo PASS || echo WARN)"
XNAT_VERSION=""
XNAT_ARTIFACT=""
XNAT_MANIFEST=""
XNAT_BUILD_METADATA=""
CATALINA_BASE=$(ps -eo args 2>/dev/null | sed -n 's/.*-Dcatalina.base=\([^ ]*\).*/\1/p' | head -n1)
TOMCAT_VERSION_SCRIPT=""
if [[ -n "$CATALINA_BASE" && -r "$CATALINA_BASE/bin/version.sh" ]]; then
  TOMCAT_VERSION_SCRIPT="$CATALINA_BASE/bin/version.sh"
elif [[ -r /opt/tomcat/bin/version.sh ]]; then
  TOMCAT_VERSION_SCRIPT="/opt/tomcat/bin/version.sh"
else
  TOMCAT_VERSION_SCRIPT=$(find /opt /usr/local /var/lib -maxdepth 5 -type f -path '*/tomcat*/bin/version.sh' -print -quit 2>/dev/null || true)
fi
TOMCAT_VERSION_OUTPUT=""
if [[ -n "$TOMCAT_VERSION_SCRIPT" ]]; then
  TOMCAT_VERSION_OUTPUT=$(run bash "$TOMCAT_VERSION_SCRIPT" \
    | sed -E 's/(-D[^ =]*(password|passwd|secret|token)[^ =]*=)[^ ]+/\1REDACTED/Ig')
fi
add_row "Tomcat version script" "$TOMCAT_VERSION_SCRIPT" "$([[ -n "$TOMCAT_VERSION_SCRIPT" ]] && echo PASS || echo WARN)"
add_pre_row "Tomcat version and build" "$TOMCAT_VERSION_OUTPUT" "$([[ "$TOMCAT_VERSION_OUTPUT" == *'Server version:'* ]] && echo PASS || echo WARN)" "Collected from the detected Tomcat bin/version.sh; credential-like JVM properties are redacted."
declare -a XNAT_SEARCH_ROOTS=()
for search_root in "$XNAT_HOME" "$CATALINA_BASE" /var/lib /opt /usr/local /data; do
  [[ -n "$search_root" && -d "$search_root" ]] && XNAT_SEARCH_ROOTS+=("$search_root")
done

# Prefer the manifest from the expanded, currently deployed Tomcat application.
# The deployment artifact is commonly renamed ROOT.war, so its filename is not
# a reliable version source.
if [[ -n "$CATALINA_BASE" && -r "$CATALINA_BASE/webapps/ROOT/META-INF/MANIFEST.MF" ]]; then
  XNAT_MANIFEST="$CATALINA_BASE/webapps/ROOT/META-INF/MANIFEST.MF"
elif ((${#XNAT_SEARCH_ROOTS[@]})); then
  XNAT_MANIFEST=$(timeout 15s find "${XNAT_SEARCH_ROOTS[@]}" -maxdepth 10 -type f \
    -path '*/webapps/ROOT/META-INF/MANIFEST.MF' -print -quit 2>/dev/null || true)
fi

if [[ -n "$XNAT_MANIFEST" && -r "$XNAT_MANIFEST" ]]; then
  XNAT_VERSION=$(awk -F': ' '$1=="Implementation-Version" {gsub(/\r/,"",$2); print $2; exit}' "$XNAT_MANIFEST")
  XNAT_BUILD_METADATA=$(awk -F': ' '
    $1 ~ /^(Application-Name|Implementation-Version|Implementation-Branch|Build-Date|Build-Number|Implementation-Sha-Full|Implementation-CleanTag|Implementation-Dirty)$/ {
      gsub(/\r/, "", $2)
      print $1 ": " $2
    }
  ' "$XNAT_MANIFEST")
fi

if ((${#XNAT_SEARCH_ROOTS[@]})); then
  XNAT_ARTIFACT=$(timeout 15s find "${XNAT_SEARCH_ROOTS[@]}" -maxdepth 10 -type f \
    \( -name 'xnat-web-*.jar' -o -name 'xnat-web-*.war' -o -name 'xnat-web*.jar' \) \
    -print -quit 2>/dev/null || true)
fi
if [[ -z "$XNAT_VERSION" && -n "$XNAT_ARTIFACT" ]]; then
  XNAT_VERSION=$(basename "$XNAT_ARTIFACT" | sed -nE 's/^xnat-web-?([0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]._-]+)?)\.(jar|war)$/\1/p')
  if [[ -z "$XNAT_VERSION" ]] && command_exists unzip; then
    XNAT_VERSION=$(unzip -p "$XNAT_ARTIFACT" META-INF/MANIFEST.MF 2>/dev/null \
      | awk -F': ' '/^(Implementation-Version|Bundle-Version):/ {gsub(/\r/,"",$2); print $2; exit}')
  fi
fi
if [[ -z "$XNAT_VERSION" && -n "$XNAT_HOME" ]]; then
  XNAT_VERSION=$(grep -RhsEo 'XNAT( version| Version| v)?[ :]?[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]_-]+)?' \
    "$XNAT_HOME/logs" 2>/dev/null | tail -n1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]_-]+)?' || true)
fi
add_row "Deployed XNAT version" "$XNAT_VERSION" "$([[ -n "$XNAT_VERSION" ]] && echo PASS || echo WARN)" "Read from the expanded Tomcat manifest first, with artifact and log fallbacks."
add_row "XNAT deployment manifest" "$XNAT_MANIFEST" "$([[ -n "$XNAT_MANIFEST" ]] && echo PASS || echo WARN)"
add_pre_row "XNAT build metadata" "$XNAT_BUILD_METADATA" "$([[ -n "$XNAT_BUILD_METADATA" ]] && echo PASS || echo WARN)" "Compare version, branch, build date, and Git SHA between institutions."
JAVA_VERSION=$(java -version 2>&1 | head -n3 || true)
add_pre_row "Java version" "$JAVA_VERSION" "$([[ -n "$JAVA_VERSION" ]] && echo PASS || echo FAIL)"
add_row "Java executable" "$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)"
add_pre_row "Java/Tomcat process" "$(ps -eo user,pid,etime,args 2>/dev/null | grep -E '[j]ava|[t]omcat|[c]atalina' | head -n10)"
add_pre_row "Listening TCP ports" "$(ss -lntp 2>/dev/null | head -n100)"
end_section
# Plugins
add_section "XNAT plugins"
PLUGIN_DIR=""
if [[ -n "$XNAT_HOME" && -d "$XNAT_HOME/plugins" ]]; then PLUGIN_DIR="$XNAT_HOME/plugins"; fi
add_row "Plugin directory" "$PLUGIN_DIR" "$([[ -n "$PLUGIN_DIR" ]] && echo PASS || echo WARN)"
PLUGIN_OUTPUT=""
XSYNC_MATCH=""
if [[ -n "$PLUGIN_DIR" ]]; then
  while IFS= read -r -d '' jar; do
    base=$(basename "$jar")
    manifest=""
    if command_exists unzip; then
      manifest=$(unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null \
        | awk -F': ' '/^(Implementation-Version|Bundle-Version|Specification-Version):/ {printf "%s=%s ", $1, $2}' \
        | tr -d '\r')
    fi
    checksum=$(sha256sum "$jar" 2>/dev/null | awk '{print substr($1,1,16)"…"}')
    PLUGIN_OUTPUT+="$base | ${manifest:-version from filename} | SHA256 $checksum"$'\n'
    [[ "$base" =~ [Xx][Ss]ync ]] && XSYNC_MATCH+="$base "$'\n'
  done < <(find "$PLUGIN_DIR" -maxdepth 1 -type f -name '*.jar' -print0 2>/dev/null | sort -z)
fi
add_pre_row "Installed plugin JARs" "$PLUGIN_OUTPUT" "$([[ -n "$PLUGIN_OUTPUT" ]] && echo PASS || echo WARN)" "Compare the complete list and checksums between institutions."
XSYNC_COUNT=$(grep -ci 'xsync' <<<"$XSYNC_MATCH" 2>/dev/null || true)
if [[ "$XSYNC_COUNT" -eq 1 && "$XSYNC_MATCH" == *1.8.1* ]]; then XSYNC_STATE=PASS
elif [[ "$XSYNC_COUNT" -gt 1 ]]; then XSYNC_STATE=FAIL
else XSYNC_STATE=WARN
fi
add_pre_row "Detected XSync plugin" "$XSYNC_MATCH" "$XSYNC_STATE" "Exactly one compatible XSync JAR should be installed; confirm 1.8.1 against the XNAT compatibility matrix."
end_section
# PostgreSQL
add_section "PostgreSQL"
PSQL_VERSION=$(psql --version 2>/dev/null || true)
PG_SERVICE=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | awk '$1 ~ /^postgresql.*\.service$/ {print $1, $4; exit}')
add_row "Client version" "$PSQL_VERSION" "$([[ -n "$PSQL_VERSION" ]] && echo PASS || echo WARN)"
add_row "Service" "$PG_SERVICE" "$([[ -n "$PG_SERVICE" ]] && echo PASS || echo INFO)" "PostgreSQL may be hosted remotely."
add_pre_row "PostgreSQL processes" "$(ps -eo user,pid,etime,args 2>/dev/null | grep '[p]ostgres' | head -n20)"
XNAT_DB_SIZE=""
XNAT_DB_ERROR=""
if command_exists psql; then
  if [[ $EUID -eq 0 ]] && command_exists runuser; then
    DB_RESULT=$(runuser -u postgres -- psql -X -A -t -v ON_ERROR_STOP=1 \
      -c "SELECT pg_size_pretty(pg_database_size('xnat'));" 2>&1 || true)
  elif [[ $EUID -eq 0 ]] && command_exists sudo; then
    DB_RESULT=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 \
      -c "SELECT pg_size_pretty(pg_database_size('xnat'));" 2>&1 || true)
  else
    DB_RESULT="Database-size query requires root access to run psql as the postgres account."
  fi
  XNAT_DB_SIZE=$(sed -nE '/^[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*(bytes|kB|MB|GB|TB)[[:space:]]*$/ {s/^[[:space:]]+//; s/[[:space:]]+$//; p; q}' <<<"$DB_RESULT")
  [[ -z "$XNAT_DB_SIZE" ]] && XNAT_DB_ERROR="$DB_RESULT"
else
  XNAT_DB_ERROR="psql is not installed locally; PostgreSQL may be hosted on another server."
fi
if [[ -n "$XNAT_DB_SIZE" ]]; then
  add_row "XNAT database size" "$XNAT_DB_SIZE" PASS "Result of pg_database_size('xnat')."
else
  add_pre_row "XNAT database size" "$XNAT_DB_ERROR" WARN "The query uses the local postgres operating-system account and assumes the database is named xnat."
fi
end_section

# Reverse proxy
add_section "Web and reverse-proxy services"
APACHE_VERSION_OUTPUT=""
APACHE_VERSION_COMMAND=""
if command_exists apachectl; then
  APACHE_VERSION_COMMAND=$(command -v apachectl)
  APACHE_VERSION_OUTPUT=$(run apachectl -v)
elif command_exists apache2ctl; then
  APACHE_VERSION_COMMAND=$(command -v apache2ctl)
  APACHE_VERSION_OUTPUT=$(run apache2ctl -v)
elif command_exists httpd; then
  APACHE_VERSION_COMMAND=$(command -v httpd)
  APACHE_VERSION_OUTPUT=$(run httpd -v)
fi
add_row "Apache version command" "$APACHE_VERSION_COMMAND" "$([[ -n "$APACHE_VERSION_COMMAND" ]] && echo PASS || echo INFO)" "INFO is expected when Apache is not installed and another reverse proxy is used."
add_pre_row "Apache version and build" "$APACHE_VERSION_OUTPUT" "$([[ "$APACHE_VERSION_OUTPUT" == *'Server version:'* ]] && echo PASS || echo INFO)"
for svc in apache2 httpd nginx haproxy; do
  state=$(systemctl is-active "$svc" 2>/dev/null || true)
  [[ "$state" == active ]] && add_row "$svc" "$state" PASS
done
PROXY_CERT_REFS=$(grep -RhsE '^[[:space:]]*(SSLCertificateFile|SSLCertificateChainFile|SSLCertificateKeyFile|ssl_certificate|ssl_certificate_key)[[:space:]]+' /etc/apache2 /etc/httpd /etc/nginx 2>/dev/null | sed -E 's/[[:space:]]+/ /g' | sort -u | head -n50)
add_pre_row "Configured TLS file references" "$PROXY_CERT_REFS" "$([[ -n "$PROXY_CERT_REFS" ]] && echo INFO || echo WARN)" "Private-key paths may be shown, but private-key contents are never read."
if [[ -n "$LOCAL_URL" ]]; then
  LOCAL_HTTP=$(curl --silent --show-error --output /dev/null --write-out 'HTTP %{http_code}; remote=%{remote_ip}; TLS=%{ssl_verify_result}; time=%{time_total}s' --max-time 12 "$LOCAL_URL" 2>&1 || true)
  add_row "Local public URL" "$LOCAL_URL"
  add_row "Local HTTPS response" "$LOCAL_HTTP" "$([[ "$LOCAL_HTTP" =~ HTTP\ (200|301|302|401|403) ]] && echo PASS || echo WARN)"
else
  add_row "Local public URL" "Not supplied" DEFERRED "Run again with --local-url https://xnat.example.org."
fi
end_section

# Firewall
add_section "Host firewall"
FIREWALL_FOUND=false
if command_exists ufw; then
  FIREWALL_FOUND=true
  UFW_OUTPUT=$(run ufw status verbose)
  add_pre_row "UFW status and exceptions" "$UFW_OUTPUT" "$([[ "$UFW_OUTPUT" == *'Status: active'* ]] && echo PASS || echo WARN)"
fi
if command_exists firewall-cmd; then
  FIREWALL_FOUND=true
  FIREWALLD_STATE=$(run firewall-cmd --state)
  FIREWALLD_RULES=$(run firewall-cmd --list-all-zones)
  add_row "firewalld state" "$FIREWALLD_STATE" "$([[ "$FIREWALLD_STATE" == running* ]] && echo PASS || echo WARN)"
  add_pre_row "firewalld zones and exceptions" "$FIREWALLD_RULES"
fi
if command_exists nft; then
  FIREWALL_FOUND=true
  NFT_OUTPUT=$(run nft list ruleset)
  add_pre_row "nftables ruleset" "$NFT_OUTPUT" "$([[ -n "$NFT_OUTPUT" ]] && echo INFO || echo WARN)"
fi
if ! $FIREWALL_FOUND; then
  add_row "Host firewall" "No supported firewall command detected" WARN "An upstream firewall may still provide enforcement."
fi
end_section

# Certificates
add_section "TLS certificates and trust"
add_pre_row "Reverse-proxy certificate references" "$PROXY_CERT_REFS" INFO
CERT_FILES=""
for cert_dir in /etc/ssl /etc/pki /etc/apache2 /etc/nginx "$XNAT_HOME/config"; do
  [[ -n "$cert_dir" && -d "$cert_dir" ]] || continue
  while IFS= read -r -d '' cert; do
    cert_info=$(openssl x509 -in "$cert" -noout -subject -issuer -dates 2>/dev/null || true)
    [[ -n "$cert_info" ]] && CERT_FILES+="$cert"$'\n'"$cert_info"$'\n\n'
  done < <(find "$cert_dir" -xdev -maxdepth 4 -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.cer' \) -print0 2>/dev/null | head -z -n 80)
done
add_pre_row "Readable local certificate files" "$CERT_FILES" INFO "Locations are reported, but private-key contents are never read or displayed. The list is capped."
JAVA_HOME_PATH=""
JAVA_BIN=$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null || true)
[[ -n "$JAVA_BIN" ]] && JAVA_HOME_PATH=$(dirname "$(dirname "$JAVA_BIN")")
CACERTS="$JAVA_HOME_PATH/lib/security/cacerts"
add_row "Java default truststore" "$CACERTS" "$([[ -r "$CACERTS" ]] && echo PASS || echo WARN)"
if [[ -n "$LOCAL_URL" ]]; then
  LOCAL_HOST=${LOCAL_URL#*://}; LOCAL_HOST=${LOCAL_HOST%%/*}; LOCAL_HOST=${LOCAL_HOST%%:*}
  LIVE_CERT=$(timeout 12s openssl s_client -connect "$LOCAL_HOST:443" -servername "$LOCAL_HOST" </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -issuer -serial -dates -ext subjectAltName 2>/dev/null || true)
  add_pre_row "Live local HTTPS certificate" "$LIVE_CERT" "$([[ -n "$LIVE_CERT" ]] && echo PASS || echo WARN)"
fi
end_section

# Storage
add_section "Storage capacity and XNAT directories"
add_pre_row "Filesystem utilization" "$(df -hT 2>/dev/null)"
FSTAB_CONFIG=""
if [[ -r /etc/fstab ]]; then
  FSTAB_CONFIG=$(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
    {
      options=""
      count=split($4, option, ",")
      for (i=1; i<=count; i++) {
        if (option[i] ~ /^(password|passwd|credentials|username|user|token|secret)=/) {
          sub(/=.*/, "=REDACTED", option[i])
        }
        options=options (i==1 ? "" : ",") option[i]
      }
      printf "%-34s %-28s %-10s %s\n", $1, $2, $3, options
    }
  ' /etc/fstab)
fi
add_pre_row "/etc/fstab configured filesystems" "$FSTAB_CONFIG" "$([[ -n "$FSTAB_CONFIG" ]] && echo PASS || echo INFO)" "Credential-like mount options are redacted. Columns: source, mountpoint, filesystem, options."
FSTAB_MOUNTPOINTS=$(awk '!/^[[:space:]]*#/ && NF >= 4 && $2 != "none" && $2 != "swap" {print $2}' /etc/fstab 2>/dev/null)
FSTAB_RUNTIME=""
while IFS= read -r mountpoint; do
  [[ -n "$mountpoint" ]] || continue
  if command_exists findmnt; then
    mounted=$(findmnt --noheadings --output TARGET,SOURCE,FSTYPE,OPTIONS --target "$mountpoint" 2>/dev/null || true)
  else
    mounted=$(mountpoint -q "$mountpoint" 2>/dev/null && echo "$mountpoint is mounted" || true)
  fi
  capacity=$(df -hT --output=target,source,fstype,size,used,avail,pcent "$mountpoint" 2>/dev/null | tail -n1 || true)
  if [[ -n "$mounted" ]]; then
    FSTAB_RUNTIME+="CONFIGURED: $mountpoint"$'\n'"MOUNTED:    $mounted"$'\n'"CAPACITY:   $capacity"$'\n\n'
  else
    FSTAB_RUNTIME+="CONFIGURED: $mountpoint"$'\n'"MOUNTED:    NO"$'\n\n'
  fi
done <<<"$FSTAB_MOUNTPOINTS"
add_pre_row "Configured mountpoint status and capacity" "$FSTAB_RUNTIME" INFO "Verifies whether each /etc/fstab mountpoint is currently mounted and reports its capacity."
if [[ -n "$XNAT_HOME" ]]; then
  for dir in archive build cache logs prearchive; do
    path="$XNAT_HOME/$dir"
    [[ -e "$path" ]] && add_row "$dir path" "$path — $(du -sh "$path" 2>/dev/null | awk '{print $1}')" INFO
  done
fi
add_pre_row "Inode utilization" "$(df -hi 2>/dev/null)"
end_section

# Peer readiness
add_section "Remote peer readiness"
add_row "Expected inbound service account" "$SERVICE_ACCOUNT" "$([[ -n "$SERVICE_ACCOUNT" ]] && echo INFO || echo DEFERRED)" "The script records only the account name; it never validates or stores its password."
if [[ -n "$PEER_FQDN" ]]; then
  DNS_RESULT=$(getent ahostsv4 "$PEER_FQDN" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd ', ' -)
  DNS_STATE=$([[ -n "$DNS_RESULT" ]] && echo PASS || echo DEFERRED)
  [[ -n "$PEER_IP" && -n "$DNS_RESULT" && ",$DNS_RESULT," != *",$PEER_IP,"* ]] && DNS_STATE=WARN
  add_row "Peer FQDN" "$PEER_FQDN"
  add_row "Peer DNS result" "$DNS_RESULT" "$DNS_STATE" "DEFERRED is expected before cross-site DNS/Layer 3 is delivered."
  PEER_ROUTE=$(ip route get "${PEER_IP:-$PEER_FQDN}" 2>/dev/null || true)
  add_pre_row "Kernel route to peer" "$PEER_ROUTE" "$([[ -n "$PEER_ROUTE" ]] && echo PASS || echo DEFERRED)"
  PEER_TCP=$(timeout 5s bash -c 'exec 3<>/dev/tcp/$1/443' _ "$PEER_FQDN" 2>&1 && echo 'TCP 443 connected' || true)
  add_row "Peer TCP 443" "$PEER_TCP" "$([[ "$PEER_TCP" == *connected* ]] && echo PASS || echo DEFERRED)"
  PEER_TLS=$(timeout 8s openssl s_client -connect "$PEER_FQDN:443" -servername "$PEER_FQDN" -verify_return_error </dev/null 2>&1 | tail -n20 || true)
  PEER_VERIFY=$(grep -E 'Verify return code: 0|Verification: OK' <<<"$PEER_TLS" || true)
  add_pre_row "Peer TLS verification" "$PEER_TLS" "$([[ -n "$PEER_VERIFY" ]] && echo PASS || echo DEFERRED)" "Do not use insecure certificate bypasses for production validation."
  PEER_HTTP=$(curl --silent --show-error --output /dev/null --write-out 'HTTP %{http_code}; remote=%{remote_ip}; TLS=%{ssl_verify_result}; time=%{time_total}s' --connect-timeout 5 --max-time 12 "https://$PEER_FQDN/" 2>&1 || true)
  add_row "Peer HTTPS response" "$PEER_HTTP" "$([[ "$PEER_HTTP" =~ HTTP\ (200|301|302|401|403) ]] && echo PASS || echo DEFERRED)"
else
  add_row "Peer endpoint" "Not supplied" DEFERRED "Run again with --peer-fqdn and optionally --peer-ip after the network design is assigned."
fi
end_section

# Follow-up checklist
add_section "Items requiring human confirmation"
add_row "XNAT version compatibility" "Compare exact XNAT patch levels at both institutions" DEFERRED
add_row "Plugin/schema compatibility" "Compare this report's plugin filenames and SHA-256 values with the peer report" DEFERRED
add_row "Local service-account project role" "Verify the inbound account has access only to the destination test project" DEFERRED
add_row "Project ownership model" "Define which institution may create or modify each subject/session/resource" DEFERRED
add_row "PHI/IRB/data-sharing approval" "Obtain institutional approval before transferring real data" DEFERRED
add_row "Backups and rollback" "Verify PostgreSQL backup, XNAT configuration backup, and archive snapshot" DEFERRED
add_row "Reverse-proxy/WAF limits" "Validate upload size, idle timeout, HTTP methods, and TLS inspection behavior" DEFERRED
add_row "Monitoring" "Assign owners for sync failures, certificate expiry, storage, and account rotation" DEFERRED
end_section

# Summaries
PASS_COUNT=$(awk -F'\t' '$1=="PASS"{n++} END{print n+0}' "$CHECK_FILE")
WARN_COUNT=$(awk -F'\t' '$1=="WARN"{n++} END{print n+0}' "$CHECK_FILE")
FAIL_COUNT=$(awk -F'\t' '$1=="FAIL"{n++} END{print n+0}' "$CHECK_FILE")
DEFER_COUNT=$(awk -F'\t' '$1=="DEFERRED"{n++} END{print n+0}' "$CHECK_FILE")

mkdir -p -- "$(dirname "$OUTPUT")"
cat >"$OUTPUT" <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>XNAT XSync Pre-work Readiness — $(html "$HOST_SHORT")</title>
<style>
:root{--bg:#08111f;--panel:#101d30;--panel2:#13243a;--text:#e7eef9;--muted:#9eb0c8;--line:#263b55;--accent:#54c7ec;--pass:#43d19e;--warn:#f4c95d;--fail:#ff6b7a;--defer:#a992e8}
*{box-sizing:border-box}body{margin:0;background:linear-gradient(145deg,#07101d,#0c1930 55%,#0b2130);color:var(--text);font:14px/1.5 Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1280px;margin:auto;padding:32px 20px 56px}.hero{border:1px solid var(--line);border-radius:18px;padding:28px;background:linear-gradient(135deg,rgba(84,199,236,.12),rgba(169,146,232,.08));box-shadow:0 18px 50px rgba(0,0,0,.25)}
h1{font-size:clamp(25px,4vw,42px);line-height:1.08;margin:0 0 8px}.subtitle{color:var(--muted);font-size:16px}.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:22px 0 0}.metric{padding:14px;border-radius:12px;background:rgba(6,15,27,.62);border:1px solid var(--line)}.metric strong{display:block;font-size:27px}.metric span{color:var(--muted);text-transform:uppercase;font-size:11px;letter-spacing:.12em}
section{margin-top:22px;border:1px solid var(--line);border-radius:15px;overflow:hidden;background:rgba(16,29,48,.94);box-shadow:0 10px 30px rgba(0,0,0,.16)}h2{font-size:18px;margin:0;padding:16px 18px;background:var(--panel2);border-bottom:1px solid var(--line)}.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse}th,td{padding:12px 16px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}tr:last-child th,tr:last-child td{border-bottom:0}th{width:23%;color:#c7d7ea;font-weight:600}td.state{width:110px;text-align:right}.value{white-space:pre-wrap;word-break:break-word}.note{color:var(--muted);font-size:12px;margin-top:4px}pre{white-space:pre-wrap;word-break:break-word;margin:0;color:#d4e5f8;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;max-height:360px;overflow:auto}
.badge{display:inline-block;border-radius:999px;padding:4px 9px;font-size:10px;font-weight:800;letter-spacing:.08em}.pass{color:#06291e;background:var(--pass)}.warn{color:#352b08;background:var(--warn)}.fail{color:#380810;background:var(--fail)}.deferred{color:#1d1237;background:var(--defer)}.info{color:#062533;background:var(--accent)}footer{color:var(--muted);text-align:center;margin-top:24px;font-size:12px}
@media(max-width:720px){.summary{grid-template-columns:repeat(2,1fr)}th{width:35%}th,td{padding:10px}.hero{padding:20px}}
@media print{body{background:#fff;color:#111}main{max-width:none;padding:0}.hero,section{box-shadow:none;background:#fff;border-color:#bbb}.subtitle,.note,footer{color:#444}h2{background:#eee}th{color:#222}pre{color:#111;max-height:none}.table-wrap{overflow:visible}}
</style></head><body><main>
<header class="hero"><h1>XNAT XSync Pre-work Readiness</h1><div class="subtitle">$(html "$HOST_FQDN") · generated $(html "$GENERATED") · read-only audit</div>
<div class="summary"><div class="metric"><strong style="color:var(--pass)">$PASS_COUNT</strong><span>Passed</span></div><div class="metric"><strong style="color:var(--warn)">$WARN_COUNT</strong><span>Warnings</span></div><div class="metric"><strong style="color:var(--fail)">$FAIL_COUNT</strong><span>Failures</span></div><div class="metric"><strong style="color:var(--defer)">$DEFER_COUNT</strong><span>Deferred</span></div></div></header>
$(cat "$BODY_FILE")
<footer>Generated by xnat-xsync-prework-audit.sh v$(html "$VERSION"). No passwords, private keys, database contents, or patient data are collected.</footer>
</main></body></html>
EOF

chmod 0640 "$OUTPUT" 2>/dev/null || true
printf '\nXNAT XSync pre-work dashboard created:\n%s\n' "$(readlink -f "$OUTPUT")"
printf 'Passed: %s | Warnings: %s | Failures: %s | Deferred: %s\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$DEFER_COUNT"

if $OPEN_REPORT; then
  if command_exists xdg-open && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    xdg-open "$OUTPUT" >/dev/null 2>&1 &
  else
    printf 'A graphical opener is not available; copy the report to an administrator workstation.\n'
  fi
fi
