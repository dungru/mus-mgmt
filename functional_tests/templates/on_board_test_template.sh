#!/bin/sh
# MUS On-board Test Contract v1 template.
# Copy this file beside your pytest wrapper and replace the TODO hooks.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
CASE_ID=""
RESTORE_MODE="always"
TEST_STATUS="ERROR"
RESTORE_STATUS="NOT_REQUIRED"
SNAPSHOT_READY=0
FINALIZED=0
INTERRUPTED=0

color_print() { printf '%b\n' "$1"; }
pass() { color_print "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { color_print "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { color_print "${YELLOW}[SKIP]${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
action() { color_print "${YELLOW}[ACTION]${NC} $1"; }

usage() {
    local code=${1:-0}
    echo "Usage: $0 -t <case-id> [--restore-mode always|on-success|never]"
    echo "       $0 -l"
    exit "$code"
}

list_cases() {
    echo "example-1  Replace this line with a readable case description"
    exit 0
}

# TODO: Validate required DUT commands/files without changing DUT state.
precondition() {
    return 0
}

# TODO: Save every DUT value that your test can change.
snapshot_dut_state() {
    SNAPSHOT_READY=1
    return 0
}

# TODO: Restore the saved values. Return non-zero on any failed action.
restore_dut_state() {
    return 0
}

# TODO: Read the DUT again and prove it matches the snapshot.
verify_restored_state() {
    return 0
}

# TODO: Implement cases using pass/fail/skip. Do not call exit here.
run_case() {
    case "$1" in
        example-1)
            action "Run the example action"
            pass "Replace with a real assertion"
            ;;
        *)
            color_print "${RED}Unknown case: $1${NC}"
            return 4
            ;;
    esac
}

emit_result() {
    printf 'MUS_RESULT_V1|case=%s|test=%s|restore=%s|passed=%s|failed=%s|skipped=%s\n' \
        "$CASE_ID" "$TEST_STATUS" "$RESTORE_STATUS" \
        "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}

finalize_run() {
    local requested_exit=$1
    local final_exit=$requested_exit
    local should_restore=0

    FINALIZED=1
    trap - EXIT HUP INT TERM

    if [ "$INTERRUPTED" -eq 1 ] || [ "$requested_exit" -eq 2 ] || [ "$requested_exit" -eq 4 ]; then
        TEST_STATUS="ERROR"
    elif [ "$SKIP_COUNT" -gt 0 ] && [ "$PASS_COUNT" -eq 0 ] && [ "$FAIL_COUNT" -eq 0 ]; then
        TEST_STATUS="SKIP"
        final_exit=77
    elif [ "$FAIL_COUNT" -gt 0 ]; then
        TEST_STATUS="FAIL"
        final_exit=1
    else
        TEST_STATUS="PASS"
        final_exit=0
    fi

    if [ "$SNAPSHOT_READY" -eq 1 ]; then
        case "$RESTORE_MODE" in
            always) should_restore=1 ;;
            on-success)
                if [ "$TEST_STATUS" = "PASS" ] || [ "$TEST_STATUS" = "SKIP" ]; then
                    should_restore=1
                else
                    RESTORE_STATUS="PRESERVED"
                fi
                ;;
            never) RESTORE_STATUS="PRESERVED" ;;
        esac
        if [ "$should_restore" -eq 1 ]; then
            if restore_dut_state && verify_restored_state; then
                RESTORE_STATUS="PASS"
            else
                RESTORE_STATUS="FAIL"
                final_exit=3
            fi
        fi
    fi

    emit_result
    exit "$final_exit"
}

on_exit() {
    local code=$?
    if [ "$FINALIZED" -eq 0 ]; then
        finalize_run "$code"
    fi
}

on_signal() {
    INTERRUPTED=1
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -t)
            shift
            [ "$#" -gt 0 ] || usage 4
            CASE_ID="$1"
            ;;
        -l) list_cases ;;
        -h) usage 0 ;;
        --restore-mode)
            shift
            [ "$#" -gt 0 ] || usage 4
            RESTORE_MODE="$1"
            ;;
        --restore-mode=*) RESTORE_MODE=${1#*=} ;;
        *) usage 4 ;;
    esac
    shift
done

[ -n "$CASE_ID" ] || usage 4
case "$RESTORE_MODE" in
    always|on-success|never) ;;
    *) usage 4 ;;
esac

trap on_exit EXIT
trap on_signal HUP INT TERM

if ! precondition; then
    exit 2
fi
if ! snapshot_dut_state; then
    exit 2
fi
run_case "$CASE_ID"
case_exit=$?
finalize_run "$case_exit"
