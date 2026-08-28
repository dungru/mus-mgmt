#!/bin/sh
# channels.json verification. POSIX sh / BusyBox ash compatible.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
TEST_TO_RUN=all; RESTORE_MODE=always; TEST_STATUS=ERROR; RESTORE_STATUS=NOT_REQUIRED
SNAPSHOT_FILE="/tmp/mus-channels-state-$$"; SNAPSHOT_READY=0; MUTATED=0; FINALIZED=0; INTERRUPTED=0

print_color() { printf '%b\n' "$1"; }
info() { print_color "${YELLOW}[INFO]${NC} $1"; }
pass() { print_color "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { print_color "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { print_color "${YELLOW}[SKIP]${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
get_all_wifi_interfaces() { ls -1 /sys/class/net 2>/dev/null | grep -E '^ra' | sort; }
get_channels_interfaces() { get_all_wifi_interfaces | grep -E '^ra[0-9]|^rax[0-9]|^rai[0-9]'; }
get_main_interfaces() { get_channels_interfaces | grep -E '^ra0$|^rax0$|^rai0$'; }
get_virtual_interfaces() { get_channels_interfaces | grep -v -E '^ra0$|^rax0$|^rai0$'; }
interface_is_up() { ifconfig "$1" 2>/dev/null | grep -q 'UP'; }
# rai* interfaces expose channels.json under /proc/mt_wifi_1/; others under /proc/mt_wifi/.
channels_file() {
	case "$1" in
		rai*) printf '/proc/mt_wifi_1/%s/channels.json\n' "$1" ;;
		*)    printf '/proc/mt_wifi/%s/channels.json\n'   "$1" ;;
	esac
}
usage() { code=${1:-0}; printf 'Usage: %s -t 1-7 [--restore-mode always|on-success|never]\n' "$0"; exit "$code"; }

snapshot_dut_state() {
	: > "$SNAPSHOT_FILE" || return 1
	for iface in $(get_all_wifi_interfaces); do
		if interface_is_up "$iface"; then state=up; else state=down; fi
		printf '%s|%s\n' "$iface" "$state" >> "$SNAPSHOT_FILE" || return 1
	done
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
	for iface in $(get_all_wifi_interfaces); do
		grep -q "^$iface|" "$SNAPSHOT_FILE" || { print_color "${RED}[RESTORE FAIL]${NC} unexpected interface $iface"; err=1; }
	done
	[ "$err" -eq 0 ] && print_color "${GREEN}[RESTORE PASS]${NC} original interface states verified"
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
	elif [ "$PASS_COUNT" -eq 0 ]; then TEST_STATUS=ERROR; final=2
	else TEST_STATUS=PASS; final=0; fi
	if [ "$SNAPSHOT_READY" -eq 1 ] && [ "$MUTATED" -eq 1 ]; then
		case "$RESTORE_MODE" in always) restore=1;; on-success) [ "$TEST_STATUS" = PASS ] && restore=1 || RESTORE_STATUS=PRESERVED;; never) RESTORE_STATUS=PRESERVED;; esac
		if [ "$restore" -eq 1 ]; then restore_dut_state && RESTORE_STATUS=PASS || { RESTORE_STATUS=FAIL; final=3; }; fi
	fi
	rm -f "$SNAPSHOT_FILE"; emit_result; exit "$final"
}
on_exit() { code=$?; [ "$FINALIZED" -eq 1 ] || finalize "$code"; }
on_signal() { INTERRUPTED=1; exit 2; }

test1() {
	for iface in $(get_main_interfaces); do file=$(channels_file "$iface"); [ -f "$file" ] && pass "$iface exposes channels.json" || fail "$iface is missing channels.json"; done
	for iface in $(get_virtual_interfaces); do file=$(channels_file "$iface"); [ -f "$file" ] && fail "$iface unexpectedly exposes channels.json" || pass "$iface correctly has no channels.json"; done
}
test2() {
	for iface in $(get_main_interfaces); do
		file=$(channels_file "$iface"); [ -f "$file" ] || { fail "$iface is missing channels.json"; continue; }
		content=$(cat "$file" 2>/dev/null)
		for field in band country_code channels all_regulatory; do printf '%s\n' "$content" | grep -q "\"$field\"" && pass "$iface contains $field" || fail "$iface is missing $field"; done
		if command -v jq >/dev/null 2>&1; then printf '%s\n' "$content" | jq . >/dev/null 2>&1 && pass "$iface contains valid JSON" || fail "$iface contains invalid JSON"; else skip 'jq unavailable; syntax validation skipped'; fi
	done
}
test3() {
	for iface in $(get_main_interfaces); do
		file=$(channels_file "$iface"); [ -f "$file" ] || { fail "$iface is missing channels.json"; continue; }; bad=0
		for i in 1 2 3 4 5 6 7 8 9 10; do cat "$file" 2>/dev/null | grep -q '"band"' || { fail "$iface read $i failed"; bad=$((bad + 1)); }; done
		[ "$bad" -eq 0 ] && pass "$iface completed 10 consistent reads"
	done
}
test4() {
	for iface in $(get_main_interfaces); do
		file=$(channels_file "$iface"); [ -f "$file" ] || { fail "$iface is missing channels.json"; continue; }
		band=$(grep -o '"band":[^,]*' "$file" 2>/dev/null | head -1 | cut -d'"' -f4)
		[ -n "$band" ] && pass "$iface reports band $band" || fail "$iface has no readable band value"
	done
}
test5() {
	for iface in $(get_main_interfaces); do
		file=$(channels_file "$iface"); [ -f "$file" ] || { fail "$iface is missing channels.json before restart"; continue; }
		before=$(grep -o '"band":[^,]*' "$file" 2>/dev/null | head -1)
		MUTATED=1
		ifconfig "$iface" down >/dev/null 2>&1 || { fail "could not bring $iface down"; continue; }; sleep 2
		[ -f "$file" ] && fail "$iface channels.json remained after down" || pass "$iface channels.json removed after down"
		ifconfig "$iface" up >/dev/null 2>&1 || { fail "could not bring $iface up"; continue; }; sleep 3
		if [ -f "$file" ]; then pass "$iface channels.json recreated"; after=$(grep -o '"band":[^,]*' "$file" 2>/dev/null | head -1); [ "$before" = "$after" ] && pass "$iface band is consistent" || fail "$iface band changed"; else fail "$iface channels.json was not recreated"; fi
	done
}
test6() {
	command -v wifi >/dev/null 2>&1 || { info 'wifi command is required'; return 2; }
	main_ifaces=$(get_main_interfaces)
	MUTATED=1
	wifi reload >/dev/null 2>&1 || { fail 'wifi reload command failed'; return; }; sleep 20
	for iface in $main_ifaces; do [ -f "$(channels_file "$iface")" ] && pass "wifi reload restored $iface channels.json" || fail "wifi reload missed $iface channels.json"; done
	wifi restart >/dev/null 2>&1 || { fail 'wifi restart command failed'; return; }; sleep 20
	for iface in $main_ifaces; do
		file=$(channels_file "$iface"); [ -f "$file" ] && pass "wifi restart restored $iface channels.json" || { fail "wifi restart missed $iface channels.json"; continue; }
		ok=0; for i in 1 2 3 4 5; do cat "$file" 2>/dev/null | grep -q '"band"' && ok=$((ok + 1)); done
		[ "$ok" -eq 5 ] && pass "$iface completed 5 reads after restart" || fail "$iface completed only $ok/5 reads"
	done
}
test7() {
	[ -d /proc/mt_wifi/band0 ] && fail '/proc/mt_wifi/band0 still exists' || pass '/proc/mt_wifi/band0 is absent'
	[ -d /proc/mt_wifi/band1 ] && fail '/proc/mt_wifi/band1 still exists' || pass '/proc/mt_wifi/band1 is absent'
	[ -d /proc/mt_wifi_1/band0 ] && fail '/proc/mt_wifi_1/band0 still exists' || pass '/proc/mt_wifi_1/band0 is absent'
	[ -d /proc/mt_wifi_1/band1 ] && fail '/proc/mt_wifi_1/band1 still exists' || pass '/proc/mt_wifi_1/band1 is absent'
}
run_test() { case "$1" in 1) test1;; 2) test2;; 3) test3;; 4) test4;; 5) test5;; 6) test6;; 7) test7;; *) return 4;; esac; }

main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-t) shift; [ "$#" -gt 0 ] || usage 4; TEST_TO_RUN=$1;; -a) TEST_TO_RUN=all;;
			--restore-mode) shift; [ "$#" -gt 0 ] || usage 4; RESTORE_MODE=$1;; --restore-mode=*) RESTORE_MODE=${1#*=};;
			-l) printf '1. presence\n2. JSON structure\n3. repeated reads\n4. band information\n5. interface restart\n6. wifi reload/restart\n7. legacy directory removal\n'; exit 0;; -h) usage 0;; *) usage 4;;
		esac; shift
	done
	case "$TEST_TO_RUN" in all|1|2|3|4|5|6|7);; *) usage 4;; esac; case "$RESTORE_MODE" in always|on-success|never);; *) usage 4;; esac
	trap on_exit EXIT; trap on_signal HUP INT TERM
	[ "$(id -u)" -eq 0 ] || { info 'Must run as root'; exit 2; }
	[ -d /proc/mt_wifi ] || [ -d /proc/mt_wifi_1 ] || { info '/proc/mt_wifi and /proc/mt_wifi_1 are unavailable'; exit 2; }
	[ -n "$(get_main_interfaces)" ] || { info 'No ra0/rax0/rai0 main interfaces found'; exit 2; }
	snapshot_dut_state || { info 'Could not snapshot interface state'; exit 2; }
	if [ "$TEST_TO_RUN" = all ]; then for number in 1 2 3 4 5 6 7; do run_test "$number" || exit $?; done; else run_test "$TEST_TO_RUN" || exit $?; fi
	finalize 0
}

main "$@"
