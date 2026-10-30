#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS+=1))
    else
        echo "  [FAIL] $desc (expected: '$expected', actual: '$actual')"; ((FAIL+=1))
    fi
}
echo "Configuration audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
sshd_config=$(sudo /usr/sbin/sshd -T 2>/dev/null) || sshd_config=''
ufw_status=$(sudo ufw status verbose 2>/dev/null) || ufw_status=''
echo '[1] SSH service'
check 'Root login disabled' no "$(awk '$1=="permitrootlogin" {print $2}' <<< "$sshd_config")"
check 'Password authentication disabled' no "$(awk '$1=="passwordauthentication" {print $2}' <<< "$sshd_config")"
# TODO 1: require at least one listening port and reject port 22.
nonstandard=$(awk '$1=="port" {n++; if ($2==22) bad=1} END {print (n>0 && !bad) ? "yes" : "no"}' <<< "$sshd_config")
check 'All SSH ports differ from 22' yes "$nonstandard"
# TODO 2: check the effective value rather than a configuration file.
check 'MaxAuthTries equals 3' 3 "$(awk '$1=="maxauthtries" {print $2}' <<< "$sshd_config")"
echo '[2] Firewall'
check 'Firewall active' active "$(awk '/^Status:/ {print $2}' <<< "$ufw_status")"
# TODO 3: extract the incoming policy from the verbose status.
check 'Default incoming policy is deny' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$ufw_status")"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo '[4] Web server'
check 'Nginx service active' active "$(systemctl is-active nginx 2>/dev/null)"
nginx_syntax=invalid
if sudo /usr/sbin/nginx -t >/dev/null 2>&1; then nginx_syntax=valid; fi
check 'Nginx configuration syntax valid' valid "$nginx_syntax"

cert_min_days="${AUDIT_CERT_MIN_DAYS:-30}"
cert_lifetime=insufficient
if [[ "$cert_min_days" =~ ^[0-9]{1,5}$ ]] && (( 10#$cert_min_days <= 36500 )); then
    if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$((10#$cert_min_days * 86400))" >/dev/null 2>&1; then
        cert_lifetime=sufficient
    fi
fi
check "Certificate valid for at least $cert_min_days days" sufficient "$cert_lifetime"

web_permissions=unsafe
if writable_paths=$(find /var/www/devops-site -perm -o+w -print 2>/dev/null) && \
   key_permissions=$(sudo stat -c '%a:%u' /etc/ssl/private/devops.key 2>/dev/null) && \
   [[ -z "$writable_paths" && "$key_permissions" == 600:0 ]]; then
    web_permissions=secure
fi
check 'No world-writable web paths; TLS key root-owned and mode 600' secure "$web_permissions"

echo "Passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
