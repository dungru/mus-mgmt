#!/bin/sh
# RRM neighbor database cross-configuration. POSIX sh / BusyBox ash compatible.
# Safety policy: run only when every target DB is empty; restore by clearing only
# the entries created by this test. The kernel log is read, never cleared.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
TEST_TO_RUN=1; RESTORE_MODE=always; TEST_STATUS=ERROR; RESTORE_STATUS=NOT_REQUIRED
ELEMENT_FILE="/tmp/mus-rrm-elements-$$"; DB_FILE="/tmp/mus-rrm-db-$$"
INTERFACES=''; ELEMENT_COUNT=0; SNAPSHOT_READY=0; FINALIZED=0; INTERRUPTED=0

print_color() { printf '%b\n' "$1"; }
info() { print_color "${YELLOW}[INFO]${NC} $1"; }
pass() { print_color "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { print_color "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
usage() { code=${1:-0}; printf 'Usage: %s -t 1 [--restore-mode always|on-success|never]\n' "$0"; exit "$code"; }

query_db() {
	iface=$1; output=$2
	wm=$(dmesg | wc -l)
	iwpriv "$iface" show NeighborReportDB >/dev/null 2>&1 || return 1
	sleep 1
	next=$((wm + 1)); dmesg | tail -n +"$next" > "$output"
	grep -q 'Total Entries:' "$output"
}

collect_elements() {
	: > "$ELEMENT_FILE" || return 1
	for proc_dir in /proc/mt_wifi /proc/mt_wifi_*; do
		[ -d "$proc_dir" ] || continue
		for path in "$proc_dir"/*/SelfNeighborReportElement; do
			[ -s "$path" ] || continue
			iface=${path%/SelfNeighborReportElement}; iface=${iface##*/}
			if grep -q "^$iface|" "$ELEMENT_FILE"; then continue; fi
			element=$(cat "$path" 2>/dev/null)
			[ -n "$element" ] || continue
			printf '%s|%s|%s\n' "$iface" "$proc_dir" "$element" >> "$ELEMENT_FILE"
			INTERFACES="$INTERFACES $iface"; ELEMENT_COUNT=$((ELEMENT_COUNT + 1))
		done
	done
	[ "$ELEMENT_COUNT" -ge 2 ]
}

require_empty_databases() {
	for iface in $INTERFACES; do
		query_db "$iface" "$DB_FILE" || { info "Cannot read NeighborReportDB for $iface"; return 1; }
		if ! grep -q 'Total Entries: 0' "$DB_FILE"; then
			info "$iface NeighborReportDB is not empty; refusing to overwrite existing DUT state"
			return 1
		fi
	done
	SNAPSHOT_READY=1
}

restore_dut_state() {
	err=0
	for iface in $INTERFACES; do
		iwpriv "$iface" set NeighborReportElementClear=1 >/dev/null 2>&1 || err=1
	done
	for iface in $INTERFACES; do
		if ! query_db "$iface" "$DB_FILE" || ! grep -q 'Total Entries: 0' "$DB_FILE"; then
			print_color "${RED}[RESTORE FAIL]${NC} $iface NeighborReportDB is not empty"
			err=1
		fi
	done
	[ "$err" -eq 0 ] && print_color "${GREEN}[RESTORE PASS]${NC} all originally-empty RRM databases verified empty"
	return "$err"
}

emit_result() {
	printf 'MUS_RESULT_V1|case=%s|test=%s|restore=%s|passed=%s|failed=%s|skipped=%s\n' \
		"$TEST_TO_RUN" "$TEST_STATUS" "$RESTORE_STATUS" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}
finalize() {
	wanted=$1; final=$wanted; restore=0; FINALIZED=1; trap - EXIT HUP INT TERM
	if [ "$INTERRUPTED" -eq 1 ] || [ "$wanted" -eq 2 ] || [ "$wanted" -eq 4 ]; then TEST_STATUS=ERROR
	elif [ "$FAIL_COUNT" -gt 0 ]; then TEST_STATUS=FAIL; final=1
	else TEST_STATUS=PASS; final=0; fi
	if [ "$SNAPSHOT_READY" -eq 1 ]; then
		case "$RESTORE_MODE" in always) restore=1;; on-success) [ "$TEST_STATUS" = PASS ] && restore=1 || RESTORE_STATUS=PRESERVED;; never) RESTORE_STATUS=PRESERVED;; esac
		if [ "$restore" -eq 1 ]; then restore_dut_state && RESTORE_STATUS=PASS || { RESTORE_STATUS=FAIL; final=3; }; fi
	fi
	rm -f "$ELEMENT_FILE" "$DB_FILE"; emit_result; exit "$final"
}
on_exit() { code=$?; [ "$FINALIZED" -eq 1 ] || finalize "$code"; }
on_signal() { INTERRUPTED=1; exit 2; }

configure_databases() {
	for iface in $INTERFACES; do
		neighbors=''; count=0
		while IFS='|' read -r other_iface other_proc element; do
			[ "$iface" = "$other_iface" ] && continue
			if [ "$count" -eq 0 ]; then neighbors=$element; else neighbors="$neighbors;$element"; fi
			count=$((count + 1))
		done < "$ELEMENT_FILE"
		iwpriv "$iface" set NeighborReportElementClear=1 >/dev/null 2>&1 || { fail "Failed to clear $iface"; continue; }
		if iwpriv "$iface" set NeighborReportElementList="len($count)nr($neighbors)" >/dev/null 2>&1; then
			pass "Configured $count neighbors on $iface"
		else fail "Failed to configure $iface"; fi
	done
}

verify_databases() {
	expected=$((ELEMENT_COUNT - 1))
	for iface in $INTERFACES; do
		query_db "$iface" "$DB_FILE" || { fail "Cannot read NeighborReportDB for $iface"; continue; }
		grep -q 'Enabled: YES' "$DB_FILE" && pass "$iface database enabled" || fail "$iface database not enabled"
		grep -q "Total Entries: $expected" "$DB_FILE" && pass "$iface has $expected entries" || fail "$iface entry count differs from $expected"
		my_element=$(grep "^$iface|" "$ELEMENT_FILE" | head -1 | cut -d'|' -f3); my_bssid=$(printf '%s\n' "$my_element" | cut -d: -f1-6)
		grep 'BSSID:' "$DB_FILE" | grep -q "$my_bssid" && fail "$iface contains its own BSSID $my_bssid" || pass "$iface excludes its own BSSID"
		while IFS='|' read -r other_iface other_proc element; do
			[ "$iface" = "$other_iface" ] && continue
			bssid=$(printf '%s\n' "$element" | cut -d: -f1-6)
			grep 'BSSID:' "$DB_FILE" | grep -q "$bssid" && pass "$iface contains $other_iface ($bssid)" || fail "$iface misses $other_iface ($bssid)"
		done < "$ELEMENT_FILE"
	done
}

main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-t) shift; [ "$#" -gt 0 ] || usage 4; TEST_TO_RUN=$1;;
			--restore-mode) shift; [ "$#" -gt 0 ] || usage 4; RESTORE_MODE=$1;;
			--restore-mode=*) RESTORE_MODE=${1#*=};; -l) printf '1. RRM neighbor database cross-configuration\n'; exit 0;; -h) usage 0;; *) usage 4;;
		esac; shift
	done
	[ "$TEST_TO_RUN" = 1 ] || usage 4; case "$RESTORE_MODE" in always|on-success|never);; *) usage 4;; esac
	trap on_exit EXIT; trap on_signal HUP INT TERM
	[ "$(id -u)" -eq 0 ] || { info 'Must run as root'; exit 2; }
	command -v iwpriv >/dev/null 2>&1 || { info 'iwpriv is required'; exit 2; }
	collect_elements || { info 'At least two RRM-capable interfaces are required'; exit 2; }
	require_empty_databases || exit 2
	configure_databases; verify_databases; finalize 0
}

main "$@"
