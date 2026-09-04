#!/usr/bin/env bash
set -euo pipefail
ACCOUNT=aetheris-node GROUP=aetheris NOLOGIN=/usr/sbin/nologin
fail(){ echo "FAIL $*" >&2; exit 1; }
blocked(){ echo "NOT_VERIFIED $*" >&2; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || blocked "required tool unavailable: $1"; }
state(){
    local out
    if out="$(stat -c '%U:%G %a' -- "$1" 2>&1)"; then printf 'PRESENT\t%s\n' "$out"; return; fi
    case "$out" in *'No such file or directory'*) echo ABSENT ;; *'Permission denied'*|*'Operation not permitted'*) echo PERMISSION_DENIED ;; *) echo "UNKNOWN $out" ;; esac
}
require_meta(){
    local p="$1" type="$2" want="$3" got; got="$(state "$p")"
    case "$got" in PRESENT$'\t'*) [ "${got#*$'\t'}" = "$want" ] || fail "metadata $p" ;; PERMISSION_DENIED*) blocked "PERMISSION_DENIED $p" ;; ABSENT*) fail "ABSENT $p" ;; *) blocked "cannot verify $p" ;; esac
    if [ "$type" = dir ]; then
        [ -d "$p" ] || fail "type $p"
    else
        [ -f "$p" ] || fail "type $p"
    fi
}
need getent; need id; need stat; need passwd
rec="$(getent passwd "$ACCOUNT" 2>/dev/null || true)"; case "$rec" in *$'\n'*) blocked 'ambiguous NSS account result' ;; esac; [ -n "$rec" ] || fail 'aetheris-node account absent'
IFS=: read -r _ _ uid gid _ home shell <<<"$rec"
[[ "$uid" =~ ^[0-9]+$ ]] || fail 'UID malformed'
group_rec="$(getent group "$GROUP" 2>/dev/null || true)"; case "$group_rec" in *$'\n'*) blocked 'ambiguous NSS group result' ;; esac; [ -n "$group_rec" ] || fail 'aetheris group absent'
expected_gid="$(cut -d: -f3 <<<"$group_rec")"; [ "$gid" = "$expected_gid" ] || fail 'primary group mismatch'
[ "$shell" = "$NOLOGIN" ] || fail 'shell mismatch'
[ "$home" = /nonexistent ] && [ ! -e "$home" ] || fail 'home directory exists or is not /nonexistent'
groups="$(id -G "$ACCOUNT" 2>/dev/null)" || blocked 'supplementary groups not verifiable'
[ "$(wc -w <<<"$groups")" -eq 1 ] && [ "$groups" = "$gid" ] || fail 'supplementary groups present'
SYS_UID_MIN="$(awk '$1 == "SYS_UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)"; SYS_UID_MAX="$(awk '$1 == "SYS_UID_MAX" { print $2 }' /etc/login.defs 2>/dev/null)"
: "${SYS_UID_MIN:=100}"; : "${SYS_UID_MAX:=$(($(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null) - 1))}"
[ "$uid" -ge "$SYS_UID_MIN" ] && [ "$uid" -le "$SYS_UID_MAX" ] || fail 'UID is outside local system range'
status="$(passwd -S "$ACCOUNT" 2>/dev/null)" || blocked 'password state not verifiable'
case "$status" in "$ACCOUNT"' L '*|"$ACCOUNT"' LK '*) ;; "$ACCOUNT"' P '*) fail 'password usable' ;; *) blocked 'password state unknown' ;; esac
if getent group docker >/dev/null 2>&1; then
    if id -nG "$ACCOUNT" | tr ' ' '\n' | grep -qx docker; then fail 'Docker group membership'; fi
fi
for p in /etc/systemd/system/aetheris-node.service /usr/lib/systemd/system/aetheris-node.service /lib/systemd/system/aetheris-node.service; do case "$(state "$p")" in ABSENT) ;; PERMISSION_DENIED*) blocked "PERMISSION_DENIED $p" ;; *) fail "pre-existing unit $p" ;; esac; done
for p in /run/aetheris/aetheris-node /var/lib/aetheris/node/aetheris-node; do case "$(state "$p")" in ABSENT) ;; PERMISSION_DENIED*) blocked "PERMISSION_DENIED $p" ;; *) fail "service leaf exists $p" ;; esac; done
require_meta /etc/aetheris dir 'root:aetheris 750'; require_meta /etc/aetheris/node dir 'root:aetheris 750'
require_meta /opt/aetheris dir 'root:aetheris 755'; require_meta /opt/aetheris/releases dir 'root:aetheris 755'; require_meta /opt/aetheris/current dir 'root:aetheris 755'
require_meta /var/lib/aetheris dir 'root:aetheris 750'; require_meta /var/lib/aetheris/node dir 'root:aetheris 750'; require_meta /var/log/aetheris dir 'root:aetheris 750'; require_meta /run/aetheris dir 'root:aetheris 755'
echo RUNTIME_IDENTITY_VERIFY=PASS
