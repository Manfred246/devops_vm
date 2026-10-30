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
echo "Passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
