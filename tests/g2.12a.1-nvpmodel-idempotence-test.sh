#!/usr/bin/env bash

set -u

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

HELPER="$ROOT_DIR/files/usr/local/sbin/aetheris-nvpmodel-idempotence-condition"
DROPIN="$ROOT_DIR/files/etc/systemd/system/nvpmodel.service.d/10-aetheris-idempotence.conf"

RC=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== SHELL SYNTAX ==="

if bash -n "$HELPER"; then
    echo "PASS helper syntax"
else
    echo "FAIL helper syntax"
    RC=1
fi

echo
echo "=== DROP-IN CONTRACT ==="

EXPECTED='ExecCondition=/usr/local/sbin/aetheris-nvpmodel-idempotence-condition'

if grep -Fxq "$EXPECTED" "$DROPIN"; then
    echo "PASS ExecCondition contract"
else
    echo "FAIL ExecCondition contract"
    RC=1
fi

if grep -Eq '^ExecStart=' "$DROPIN"; then
    echo "FAIL vendor ExecStart overridden"
    RC=1
else
    echo "PASS vendor ExecStart preserved"
fi

echo
echo "=== TEST FIXTURE ==="

FAKE_NVPMODEL="$TMP_DIR/nvpmodel"
STATUS_FILE="$TMP_DIR/status"
QUERY_FILE="$TMP_DIR/query"

cat > "$FAKE_NVPMODEL" <<'FAKE'
#!/usr/bin/env bash
cat "$AETHERIS_TEST_QUERY_FILE"
exit "${AETHERIS_TEST_QUERY_RC:-0}"
FAKE

chmod +x "$FAKE_NVPMODEL"

run_condition() {
    AETHERIS_NVPMODEL_BIN="$FAKE_NVPMODEL" \
    AETHERIS_NVPMODEL_STATUS_FILE="$STATUS_FILE" \
    AETHERIS_TEST_QUERY_FILE="$QUERY_FILE" \
    AETHERIS_TEST_QUERY_RC="${AETHERIS_TEST_QUERY_RC:-0}" \
        "$HELPER"
}

echo
echo "=== CASE 1 — CURRENT == PERSISTED ==="

printf 'NV Power Mode: MAXN_SUPER\n2\n' > "$QUERY_FILE"
printf 'pmode:0002' > "$STATUS_FILE"

run_condition
CASE1_RC=$?

echo "CASE1_RC=$CASE1_RC"

if [ "$CASE1_RC" -eq 1 ]; then
    echo "PASS equal state skips redundant NVIDIA apply"
else
    echo "FAIL equal state expected rc=1"
    RC=1
fi

echo
echo "=== CASE 2 — CURRENT != PERSISTED ==="

printf 'NV Power Mode: 25W\n1\n' > "$QUERY_FILE"
printf 'pmode:0002' > "$STATUS_FILE"

run_condition
CASE2_RC=$?

echo "CASE2_RC=$CASE2_RC"

if [ "$CASE2_RC" -eq 0 ]; then
    echo "PASS mismatch delegates to NVIDIA"
else
    echo "FAIL mismatch expected rc=0"
    RC=1
fi

echo
echo "=== CASE 3 — QUERY FAILURE ==="

printf 'unused\n' > "$QUERY_FILE"
printf 'pmode:0002' > "$STATUS_FILE"

AETHERIS_TEST_QUERY_RC=9
export AETHERIS_TEST_QUERY_RC

run_condition
CASE3_RC=$?

unset AETHERIS_TEST_QUERY_RC

echo "CASE3_RC=$CASE3_RC"

if [ "$CASE3_RC" -eq 0 ]; then
    echo "PASS query failure delegates to NVIDIA"
else
    echo "FAIL query failure expected rc=0"
    RC=1
fi

echo
echo "=== CASE 4 — MALFORMED CURRENT MODE ==="

printf 'NV Power Mode: UNKNOWN\nnot-a-number\n' > "$QUERY_FILE"
printf 'pmode:0002' > "$STATUS_FILE"

run_condition
CASE4_RC=$?

echo "CASE4_RC=$CASE4_RC"

if [ "$CASE4_RC" -eq 0 ]; then
    echo "PASS malformed current mode delegates to NVIDIA"
else
    echo "FAIL malformed current mode expected rc=0"
    RC=1
fi

echo
echo "=== CASE 5 — MALFORMED PERSISTED MODE ==="

printf 'NV Power Mode: MAXN_SUPER\n2\n' > "$QUERY_FILE"
printf 'invalid-status' > "$STATUS_FILE"

run_condition
CASE5_RC=$?

echo "CASE5_RC=$CASE5_RC"

if [ "$CASE5_RC" -eq 0 ]; then
    echo "PASS malformed persisted mode delegates to NVIDIA"
else
    echo "FAIL malformed persisted mode expected rc=0"
    RC=1
fi

echo
echo "=== CASE 6 — STATUS ABSENT ==="

rm -f "$STATUS_FILE"

run_condition
CASE6_RC=$?

echo "CASE6_RC=$CASE6_RC"

if [ "$CASE6_RC" -eq 0 ]; then
    echo "PASS missing status delegates to NVIDIA"
else
    echo "FAIL missing status expected rc=0"
    RC=1
fi

echo
echo "============================================================"

if [ "$RC" -eq 0 ]; then
    echo "G2.12A.1_NVPMODEL_IDEMPOTENCE_TEST=PASS"
else
    echo "G2.12A.1_NVPMODEL_IDEMPOTENCE_TEST=FAIL"
fi

echo "============================================================"

exit "$RC"
