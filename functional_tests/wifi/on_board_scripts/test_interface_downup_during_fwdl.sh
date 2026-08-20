#!/bin/sh
# MTK first-BSS firmware-download interruption regression.
# POSIX sh / BusyBox ash compatible. This test deliberately deletes Wi-Fi
# netdevs, then recreates and verifies the configured Wi-Fi interface state.

PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
TEST_TO_RUN=all; RESTORE_MODE=always; TEST_STATUS=ERROR; RESTORE_STATUS=NOT_REQUIRED
IFACES=''; IFACE=''; SIGINT_DELAY=${SIGINT_DELAY:-4}; ITERATIONS=${N:-5}
SNAPSHOT_FILE="/tmp/mus-fwdl-state-$$"; SNAPSHOT_READY=0; FINALIZED=0; INTERRUPTED=0

pass() { printf '  PASS: %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '  FAIL: %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { printf '  INFO: %s\n' "$1"; }
uptime_now() { awk '{print $1}' /proc/uptime; }
dmesg_wm() { dmesg | wc -l; }
interface_is_up() { ifconfig "$1" 2>/dev/null | grep -q 'UP'; }
usage() {
	code=${1:-0}
	printf 'Usage: %s -t 1|2|3|4 [--restore-mode MODE] [ifname ...]\n' "$0"
	printf 'Environment: N=<iterations> SIGINT_DELAY=<seconds>\n'
	exit "$code"
}

snapshot_dut_state() {
	: > "$SNAPSHOT_FILE" || return 1
	for path in /sys/class/net/ra* /sys/class/net/apcli*; do
		[ -e "$path" ] || continue; iface=${path##*/}
		if interface_is_up "$iface"; then state=up; else state=down; fi
		printf '%s|%s\n' "$iface" "$state" >> "$SNAPSHOT_FILE" || return 1
	done
	[ -s "$SNAPSHOT_FILE" ] || return 1
	SNAPSHOT_READY=1
}

restore_dut_state() {
	err=0; info 'Restoring configured Wi-Fi stack with wifi restart'
	wifi restart >/dev/null 2>&1 || err=1
	remaining=30
	while [ "$remaining" -gt 0 ]; do
		missing=0
		while IFS='|' read -r iface state; do [ -e "/sys/class/net/$iface" ] || missing=1; done < "$SNAPSHOT_FILE"
		[ "$missing" -eq 0 ] && break
		sleep 1; remaining=$((remaining - 1))
	done
	while IFS='|' read -r iface state; do
		if [ ! -e "/sys/class/net/$iface" ]; then printf '  RESTORE FAIL: missing %s\n' "$iface"; err=1; continue; fi
		ifconfig "$iface" "$state" >/dev/null 2>&1 || err=1
	done < "$SNAPSHOT_FILE"
	sleep 2
	while IFS='|' read -r iface state; do
		if [ "$state" = up ]; then interface_is_up "$iface" || err=1
		else interface_is_up "$iface" && err=1; fi
	done < "$SNAPSHOT_FILE"
	for path in /sys/class/net/ra* /sys/class/net/apcli*; do
		[ -e "$path" ] || continue; iface=${path##*/}
		grep -q "^$iface|" "$SNAPSHOT_FILE" || { printf '  RESTORE FAIL: unexpected interface %s\n' "$iface"; err=1; }
	done
	[ "$err" -eq 0 ] && printf '  RESTORE PASS: configured interfaces and original states verified\n'
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
	rm -f "$SNAPSHOT_FILE"; emit_result; exit "$final"
}
on_exit() { code=$?; [ "$FINALIZED" -eq 1 ] || finalize "$code"; }
on_signal() { INTERRUPTED=1; exit 2; }

check_up() {
	flags=$(cat "/sys/class/net/$IFACE/flags" 2>/dev/null || printf '0x0')
	decimal=$(printf '%d' "$flags" 2>/dev/null || printf '0')
	[ $((decimal & 1)) -eq 1 ]
}
ensure_down() { ifconfig "$IFACE" down 2>/dev/null; sleep 1; }
check_dmesg_since() {
	if dmesg | tail -n +"$1" | grep -q "$2"; then fail "$3 appeared in dmesg"; else pass "no $3 in dmesg"; fi
}

test1() {
	info "SIGINT during ifconfig $IFACE up at ${SIGINT_DELAY}s"
	ensure_down; wm=$(dmesg_wm); start=$(uptime_now)
	ifconfig "$IFACE" up & pid=$!; sleep "$SIGINT_DELAY"; kill -INT "$pid" 2>/dev/null; wait "$pid"; rc=$?
	end=$(uptime_now); elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.2f", e-s}')
	[ "$rc" -eq 0 ] && pass 'ifconfig exit=0' || fail "ifconfig exit=$rc"
	check_up && pass 'interface IFF_UP set' || fail 'interface IFF_UP clear'
	next=$((wm + 1)); check_dmesg_since "$next" 'kthread_run.*err -4' 'kthread_run -EINTR'
	check_dmesg_since "$next" 'MlmeInit failed' 'MlmeInit failure'
	check_dmesg_since "$next" 'unable to start Mlme' 'MlmeThread start failure'
	check_dmesg_since "$next" 'mt_wifi_init  fail' 'mt_wifi_init failure'
	awk -v e="$elapsed" 'BEGIN{exit (e<15)?0:1}' && pass "up completed in <15s (${elapsed}s)" || fail "up took >=15s (${elapsed}s)"
}

test2() {
	for delay in 1 2 3 4 5 6 8; do
		ensure_down; wm=$(dmesg_wm); start=$(uptime_now)
		ifconfig "$IFACE" up & pid=$!; sleep "$delay"; kill -INT "$pid" 2>/dev/null; wait "$pid"; rc=$?
		end=$(uptime_now); elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.2f", e-s}'); next=$((wm + 1))
		if [ "$rc" -eq 0 ] && check_up && ! dmesg | tail -n +"$next" | grep -q 'err -4\|mt_wifi_init  fail'; then pass "SIGINT@${delay}s up OK (${elapsed}s)"; else fail "SIGINT@${delay}s failed rc=$rc (${elapsed}s)"; fi
	done
}

test3() {
	i=1
	while [ "$i" -le "$ITERATIONS" ]; do
		ensure_down; ifconfig "$IFACE" up & pid=$!; sleep "$SIGINT_DELAY"; kill -INT "$pid" 2>/dev/null; wait "$pid"; rc=$?
		if [ "$rc" -ne 0 ] || ! check_up; then fail "iteration $i failed (rc=$rc)"; return; fi
		i=$((i + 1))
	done
	pass "all $ITERATIONS SIGINT iterations passed"
}

test4() {
	i=1
	while [ "$i" -le "$ITERATIONS" ]; do
		ensure_down; ifconfig "$IFACE" up >/dev/null 2>&1 || { fail "iteration $i up command failed"; return; }
		check_up || { fail "iteration $i interface not UP"; return; }
		ifconfig "$IFACE" down >/dev/null 2>&1 || { fail "iteration $i down command failed"; return; }
		i=$((i + 1))
	done
	pass "all $ITERATIONS normal cycles passed"
}

purge_wifi_netdevs() {
	for path in /sys/class/net/ra* /sys/class/net/apcli*; do
		[ -e "$path" ] || continue; iface=${path##*/}; info "Removing $iface"
		ip link set dev "$iface" down 2>/dev/null || ifconfig "$iface" down 2>/dev/null
		ip link del dev "$iface" 2>/dev/null || iw dev "$iface" del 2>/dev/null || true
	done
}

main() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-t) shift; [ "$#" -gt 0 ] || usage 4; TEST_TO_RUN=$1;;
			--restore-mode) shift; [ "$#" -gt 0 ] || usage 4; RESTORE_MODE=$1;;
			--restore-mode=*) RESTORE_MODE=${1#*=};; -l) printf '1. single SIGINT\n2. timing sweep\n3. SIGINT stress\n4. normal cycles\n'; exit 0;; -h) usage 0;; -*) usage 4;; *) IFACES="$IFACES $1";;
		esac; shift
	done
	case "$TEST_TO_RUN" in 1|2|3|4);; *) usage 4;; esac; case "$RESTORE_MODE" in always|on-success|never);; *) usage 4;; esac
	[ -n "$IFACES" ] || IFACES='rax0 rai0'
	trap on_exit EXIT; trap on_signal HUP INT TERM
	[ "$(id -u)" -eq 0 ] || { info 'Must run as root'; exit 2; }
	command -v wifi >/dev/null 2>&1 || { info 'wifi command is required for verified recovery'; exit 2; }
	for IFACE in $IFACES; do [ -e "/sys/class/net/$IFACE" ] || { info "Required interface missing before test: $IFACE"; exit 2; }; done
	snapshot_dut_state || { info 'Could not snapshot Wi-Fi interface state'; exit 2; }
	purge_wifi_netdevs
	for IFACE in $IFACES; do
		case "$TEST_TO_RUN" in 1) test1;; 2) test2;; 3) test3;; 4) test4;; esac
	done
	finalize 0
}

main "$@"
