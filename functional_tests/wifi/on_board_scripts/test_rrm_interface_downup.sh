#!/bin/sh
# RRM interface down/up verification. POSIX sh / BusyBox ash compatible.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
TEST_TO_RUN=1; RESTORE_MODE=always; TEST_STATUS=ERROR; RESTORE_STATUS=NOT_REQUIRED
PAIR_FILE="/tmp/mus-rrm-pairs-$$"; SNAPSHOT_FILE="/tmp/mus-rrm-state-$$"
SNAPSHOT_READY=0; FINALIZED=0; INTERRUPTED=0

print_color() { printf '%b\n' "$1"; }
info() { print_color "${YELLOW}[INFO]${NC} $1"; }
pass() { print_color "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { print_color "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
interface_is_up() { ifconfig "$1" 2>/dev/null | grep -q 'UP'; }

usage() { code=${1:-0}; printf 'Usage: %s -t 1 [--restore-mode always|on-success|never]\n' "$0"; exit "$code"; }

discover_interfaces() {
	: > "$PAIR_FILE" || return 1
	for proc_dir in /proc/mt_wifi /proc/mt_wifi_*; do
		[ -d "$proc_dir" ] || continue
		for path in "$proc_dir"/*/SelfNeighborReportElement; do
			[ -f "$path" ] || continue
			iface=${path%/SelfNeighborReportElement}; iface=${iface##*/}
			if ifconfig "$iface" >/dev/null 2>&1 && ! grep -q "^$iface|" "$PAIR_FILE"; then
				printf '%s|%s\n' "$iface" "$proc_dir" >> "$PAIR_FILE"
			fi
		done
	done
	[ -s "$PAIR_FILE" ]
}

snapshot_dut_state() {
	: > "$SNAPSHOT_FILE" || return 1
	while IFS='|' read -r iface proc_dir; do
		[ -n "$iface" ] || continue
		if interface_is_up "$iface"; then state=up; else state=down; fi
		printf '%s|%s\n' "$iface" "$state" >> "$SNAPSHOT_FILE" || return 1
	done < "$PAIR_FILE"
	SNAPSHOT_READY=1
}

restore_dut_state() {
	err=0
	while IFS='|' read -r iface state; do
		[ -e "/sys/class/net/$iface" ] || { print_color "${RED}[RESTORE FAIL]${NC} missing $iface"; err=1; continue; }
		ifconfig "$iface" "$state" >/dev/null 2>&1 || err=1
	done < "$SNAPSHOT_FILE"
	sleep 2
	while IFS='|' read -r iface state; do
		if [ "$state" = up ]; then interface_is_up "$iface" || err=1
		else interface_is_up "$iface" && err=1; fi
	done < "$SNAPSHOT_FILE"
	[ "$err" -eq 0 ] && print_color "${GREEN}[RESTORE PASS]${NC} original interface states verified"
	return "$err"
}

emit_result() {
	printf 'MUS_RESULT_V1|case=%s|test=%s|restore=%s|passed=%s|failed=%s|skipped=%s\n' \
		"$TEST_TO_RUN" "$TEST_STATUS" "$RESTORE_STATUS" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}

finalize() {
	wanted=$1; final=$wanted; restore=0
	FINALIZED=1; trap - EXIT HUP INT TERM
	if [ "$INTERRUPTED" -eq 1 ] || [ "$wanted" -eq 2 ] || [ "$wanted" -eq 4 ]; then TEST_STATUS=ERROR
	elif [ "$FAIL_COUNT" -gt 0 ]; then TEST_STATUS=FAIL; final=1
	else TEST_STATUS=PASS; final=0; fi
	if [ "$SNAPSHOT_READY" -eq 1 ]; then
		case "$RESTORE_MODE" in always) restore=1;; on-success) [ "$TEST_STATUS" = PASS ] && restore=1 || RESTORE_STATUS=PRESERVED;; never) RESTORE_STATUS=PRESERVED;; esac
		if [ "$restore" -eq 1 ]; then restore_dut_state && RESTORE_STATUS=PASS || { RESTORE_STATUS=FAIL; final=3; }; fi
	fi
	rm -f "$PAIR_FILE" "$SNAPSHOT_FILE"; emit_result; exit "$final"
}

on_exit() { code=$?; [ "$FINALIZED" -eq 1 ] || finalize "$code"; }
on_signal() { INTERRUPTED=1; exit 2; }

test_interface() {
	iface=$1; proc_dir=$2; info "Testing $iface from $proc_dir"
	ifconfig "$iface" down >/dev/null 2>&1; sleep 1
	interface_is_up "$iface" && fail "$iface failed to go DOWN" || pass "$iface is DOWN"
	ifconfig "$iface" up >/dev/null 2>&1; sleep 2
	interface_is_up "$iface" && pass "$iface is UP" || fail "$iface failed to go UP"
	proc_file="$proc_dir/$iface/SelfNeighborReportElement"
	# procfs reports stat size 0 even when a read returns content.
	if [ -f "$proc_file" ]; then element=$(cat "$proc_file" 2>/dev/null); else element=''; fi
	if [ -n "$element" ]; then pass "$proc_file is readable and non-empty"; else fail "$proc_file is missing or empty"; fi
	if command -v iwpriv >/dev/null 2>&1; then
		iwpriv "$iface" show SelfNeighborReportElement >/dev/null 2>&1 \
			&& pass "iwpriv SelfNeighborReportElement works on $iface" \
			|| info "iwpriv show is unsupported on $iface; procfs result remains authoritative"
	fi
}

main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-t) shift; [ "$#" -gt 0 ] || usage 4; TEST_TO_RUN=$1;;
			--restore-mode) shift; [ "$#" -gt 0 ] || usage 4; RESTORE_MODE=$1;;
			--restore-mode=*) RESTORE_MODE=${1#*=};; -l) printf '1. RRM interface down/up recovery\n'; exit 0;; -h) usage 0;; *) usage 4;;
		esac; shift
	done
	[ "$TEST_TO_RUN" = 1 ] || usage 4
	case "$RESTORE_MODE" in always|on-success|never);; *) usage 4;; esac
	trap on_exit EXIT; trap on_signal HUP INT TERM
	[ "$(id -u)" -eq 0 ] || { info 'Must run as root'; exit 2; }
	discover_interfaces || { info 'No RRM-capable Wi-Fi interfaces found'; exit 2; }
	snapshot_dut_state || { info 'Could not snapshot interface state'; exit 2; }
	while IFS='|' read -r iface proc_dir; do test_interface "$iface" "$proc_dir"; done < "$PAIR_FILE"
	finalize 0
}

main "$@"
