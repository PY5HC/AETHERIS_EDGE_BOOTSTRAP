#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCOUNT=aetheris-node GROUP=aetheris NOLOGIN=/usr/sbin/nologin
PATH_PREFIX=
if [ "${AETHERIS_RUNTIME_IDENTITY_TEST_MODE:-0}" = 1 ]; then
    NOLOGIN="${AETHERIS_TEST_NOLOGIN_PATH:-$NOLOGIN}"
    PATH_PREFIX="${AETHERIS_TEST_PATH_PREFIX:-}"
fi
target(){ printf '%s%s' "$PATH_PREFIX" "$1"; }
fail(){ echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || fail "required command unavailable: $1"; }
need_exec(){ [ -x "$1" ] || fail "required executable unavailable: $1"; }

path_state(){
    local path="$1" out rc
    if out="$(stat -c '%U:%G %a' -- "$path" 2>&1)"; then printf 'PRESENT\t%s\n' "$out"; return; fi
    rc=$?
    case "$out" in
        *'No such file or directory'*) echo ABSENT ;;
        *'Permission denied'*|*'Operation not permitted'*) echo PERMISSION_DENIED ;;
        *) echo "UNKNOWN $out"; return "$rc" ;;
    esac
}
require_path(){
    local path="$1" type="$2" expected="$3" state meta
    state="$(path_state "$path")" || fail "cannot inspect $path"
    case "$state" in
        PRESENT$'\t'*) meta="${state#*$'\t'}"; [ "$meta" = "$expected" ] || fail "metadata mismatch for $path: $meta" ;;
        PERMISSION_DENIED*) fail "PERMISSION_DENIED: $path" ;;
        ABSENT*) fail "ABSENT: $path" ;;
        *) fail "cannot classify $path: $state" ;;
    esac
    if [ "$type" = dir ]; then
        [ -d "$path" ] || fail "type mismatch: $path"
    else
        [ -f "$path" ] || fail "type mismatch: $path"
    fi
}
require_absent(){
    local path="$1" state; state="$(path_state "$path")" || fail "cannot inspect $path"
    case "$state" in
        ABSENT) ;; PERMISSION_DENIED*) fail "PERMISSION_DENIED: $path" ;;
        PRESENT*) fail "pre-existing path: $path" ;; *) fail "cannot classify $path: $state" ;;
    esac
}
validate_repo(){
    [ -d "$ROOT_DIR/.git" ] || fail 'repository authority unavailable'
    [ "$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" = "$ROOT_DIR" ] || fail 'repository root mismatch'
    if [ -n "${AETHERIS_EXPECTED_BRANCH:-}" ]; then
        [ "$(git -C "$ROOT_DIR" branch --show-current)" = "$AETHERIS_EXPECTED_BRANCH" ] || fail 'unexpected repository branch'
    fi
    if [ -n "${AETHERIS_EXPECTED_HEAD:-}" ]; then
        [ "$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)" = "$AETHERIS_EXPECTED_HEAD" ] || fail 'unexpected repository HEAD'
    fi
    for f in docs/G3.0-node-bootstrap-contract.md files/usr/lib/tmpfiles.d/aetheris.conf scripts/apply-node-contract.sh scripts/verify-node-contract.sh templates/node-identity.env.template templates/capabilities.json.template; do
        [ -f "$ROOT_DIR/$f" ] || fail "missing canonical repository file: $f"
    done
}
account_record(){ getent passwd "$ACCOUNT" 2>/dev/null || true; }
require_single_or_empty(){
    case "$1" in *$'\n'*) fail "ambiguous NSS result for $2" ;; esac
}
validate_existing_account(){
    local rec uid gid home shell groups expected_gid status
    rec="$(account_record)"; require_single_or_empty "$rec" "$ACCOUNT"; [ -n "$rec" ] || return 1
    IFS=: read -r _ _ uid gid _ home shell <<<"$rec"
    [[ "$uid" =~ ^[0-9]+$ ]] || fail 'existing account UID malformed'
    group_rec="$(getent group "$GROUP" 2>/dev/null || true)"; require_single_or_empty "$group_rec" "$GROUP"
    expected_gid="$(cut -d: -f3 <<<"$group_rec")"
    [ "$gid" = "$expected_gid" ] || fail 'existing account primary GID mismatch'
    [ "$shell" = "$NOLOGIN" ] || fail 'existing account shell mismatch'
    [ "$home" = /nonexistent ] && [ ! -e "$home" ] || fail 'existing account home mismatch'
    groups="$(id -G "$ACCOUNT" 2>/dev/null)" || fail 'supplementary groups NOT_VERIFIED'
    [ "$(wc -w <<<"$groups")" -eq 1 ] && [ "$groups" = "$gid" ] || fail 'existing account has supplementary groups'
    status="$(passwd -S "$ACCOUNT" 2>/dev/null)" || fail 'password state NOT_VERIFIED'
    case "$status" in
        "$ACCOUNT"' L '*|"$ACCOUNT"' LK '*) ;; "$ACCOUNT"' P '*) fail 'existing account password is usable' ;;
        *) fail 'password state NOT_VERIFIED' ;;
    esac
    [ -n "$uid" ] || fail 'existing account UID empty'
    SYS_UID_MIN="$(awk '$1 == "SYS_UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)"; SYS_UID_MAX="$(awk '$1 == "SYS_UID_MAX" { print $2 }' /etc/login.defs 2>/dev/null)"
    : "${SYS_UID_MIN:=100}"; : "${SYS_UID_MAX:=$(($(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null) - 1))}"
    [ "$uid" -ge "$SYS_UID_MIN" ] && [ "$uid" -le "$SYS_UID_MAX" ] || fail 'existing account UID is outside local system range'
    echo AETHERIS_NODE_EXISTING_EXACT=YES
}
validate_preconditions(){
    need_cmd git; need_cmd getent; need_cmd id; need_cmd stat; need_cmd passwd; need_cmd useradd; need_exec "$NOLOGIN"
    validate_repo
    group_rec="$(getent group "$GROUP" 2>/dev/null || true)"; require_single_or_empty "$group_rec" "$GROUP"
    [ -n "$group_rec" ] || fail 'aetheris group absent'
    collision="$(getent group "$ACCOUNT" 2>/dev/null || true)"; [ -z "$collision" ] || fail 'unexpected aetheris-node group collision'
    local account; account="$(account_record)"; require_single_or_empty "$account" "$ACCOUNT"
    if [ -n "$account" ]; then validate_existing_account; else echo AETHERIS_NODE_EXISTING_EXACT=NO; fi
    require_path "$(target /etc/aetheris)" dir 'root:aetheris 750'
    require_path "$(target /etc/aetheris/node)" dir 'root:aetheris 750'
    require_path "$(target /opt/aetheris)" dir 'root:aetheris 755'
    require_path "$(target /opt/aetheris/releases)" dir 'root:aetheris 755'
    require_path "$(target /opt/aetheris/current)" dir 'root:aetheris 755'
    require_path "$(target /var/lib/aetheris)" dir 'root:aetheris 750'
    require_path "$(target /var/lib/aetheris/node)" dir 'root:aetheris 750'
    require_path "$(target /var/log/aetheris)" dir 'root:aetheris 750'
    require_path "$(target /run/aetheris)" dir 'root:aetheris 755'
    require_absent "$(target /run/aetheris/aetheris-node)"
    require_absent "$(target /var/lib/aetheris/node/aetheris-node)"
    for p in /etc/systemd/system/aetheris-node.service /usr/lib/systemd/system/aetheris-node.service /lib/systemd/system/aetheris-node.service; do require_absent "$(target "$p")"; done
    if [ -n "$account" ] && getent group docker >/dev/null 2>&1; then
        if id -nG "$ACCOUNT" | tr ' ' '\n' | grep -qx docker; then
            fail 'Docker authorization already present'
        fi
    fi
}
validate_preconditions
# LAST_VALIDATION_LINE: validate_preconditions has completed successfully.
if [ -n "$(account_record)" ]; then echo 'AETHERIS runtime identity already exact; semantic no-op'; exit 0; fi
# FIRST_PERSISTENT_MUTATION_LINE: useradd is the sole intended mutation.
useradd --system --no-user-group --gid "$GROUP" --shell "$NOLOGIN" --home-dir /nonexistent --no-create-home --password '!' "$ACCOUNT"
echo 'AETHERIS runtime identity created'
