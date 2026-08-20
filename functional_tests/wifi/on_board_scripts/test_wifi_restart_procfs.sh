#!/bin/sh
# WiFi Restart Procfs Test - Verify procfs behavior during interface restart

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RESTORE_MODE="always"
TEST_TO_RUN="all"
TEST_STATUS="ERROR"
RESTORE_STATUS="NOT_REQUIRED"
SNAPSHOT_FILE="/tmp/mus-wifi-state-$$"
SNAPSHOT_READY=0
FINALIZED=0
INTERRUPTED=0

color_print() { printf '%b\n' "$1"; }
pass() { color_print "${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { color_print "${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { color_print "${YELLOW}[SKIP]${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
info() { color_print "${YELLOW}[INFO]${NC} $1"; }

# Print usage
usage() {
    local exit_code=${1:-0}
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t <num>    Run specific test number (1-7)"
    echo "  -a          Run all tests (default)"
    echo "  -l          List available tests"
    echo "  -h          Show this help message"
    echo "  --restore-mode <always|on-success|never>"
    echo ""
    echo "Examples:"
    echo "  $0              # Run all tests"
    echo "  $0 -t 1         # Run test 1 only"
    echo "  $0 -t 5         # Run test 5 only"
    echo "  $0 -l           # List all tests"
    exit "$exit_code"
}

# List available tests
list_tests() {
    echo "Available Tests:"
    echo "  1. Interface bring-up creates proc entries"
    echo "  2. Interface restart preserves other interfaces"
    echo "  3. Multi-interface stability"
    echo "  4. Rapid restart stress test (5 cycles)"
    echo "  5. All interfaces restart (main 20s wait)"
    echo "  6. wifi reload command"
    echo "  7. wifi restart command"
    exit 0
}

# Get all ra* interfaces dynamically (include ra*, rai*, rax*)
get_ra_interfaces() {
	ls -1 /sys/class/net/ 2>/dev/null | grep -E '^ra' | sort
}

# Get main interfaces (ra0, rax0, rai0) - those that load firmware
get_main_interfaces() {
	get_ra_interfaces | grep -E '^ra0$|^rax0$|^rai0$'
}

# Get virtual interfaces (ra1, ra2, rax1, rai1, etc.)
get_virtual_interfaces() {
	get_ra_interfaces | grep -v -E '^ra0$|^rax0$|^rai0$'
}

# Get first interface (main interface for band 0)
get_first_interface() {
	get_ra_interfaces | head -1
}

# Get procfs path for interface
# rai* interfaces use /proc/mt_wifi_1/, others use /proc/mt_wifi/
get_procfs_path() {
	local iface=$1
	if echo "$iface" | grep -q '^rai'; then
		echo "/proc/mt_wifi_1/$iface"
	else
		echo "/proc/mt_wifi/$iface"
	fi
}

# Get procfs base directory for interface
get_procfs_base() {
	local iface=$1
	if echo "$iface" | grep -q '^rai'; then
		echo "/proc/mt_wifi_1"
	else
		echo "/proc/mt_wifi"
	fi
}

# MUS On-board Test Contract v1 lifecycle
interface_is_up() {
	ifconfig "$1" 2>/dev/null | grep -q 'UP'
}

snapshot_dut_state() {
	: > "$SNAPSHOT_FILE" || return 1
	for iface in $(get_ra_interfaces); do
		if interface_is_up "$iface"; then
			printf '%s|up\n' "$iface" >> "$SNAPSHOT_FILE" || return 1
		else
			printf '%s|down\n' "$iface" >> "$SNAPSHOT_FILE" || return 1
		fi
	done
	SNAPSHOT_READY=1
	info "Captured pre-test interface state in $SNAPSHOT_FILE"
}

restore_dut_state() {
	local restore_failed=0
	local iface
	local expected_state

	info "Restoring pre-test interface state..."
	while IFS='|' read -r iface expected_state; do
		[ -n "$iface" ] || continue
		if [ ! -e "/sys/class/net/$iface" ]; then
			color_print "${RED}[RESTORE FAIL]${NC} Interface missing: $iface"
			restore_failed=1
			continue
		fi
		if ! ifconfig "$iface" "$expected_state" >/dev/null 2>&1; then
			color_print "${RED}[RESTORE FAIL]${NC} ifconfig $iface $expected_state"
			restore_failed=1
		fi
	done < "$SNAPSHOT_FILE"
	sleep 2

	while IFS='|' read -r iface expected_state; do
		[ -n "$iface" ] || continue
		if [ "$expected_state" = "up" ]; then
			if ! interface_is_up "$iface"; then
				color_print "${RED}[RESTORE FAIL]${NC} $iface is not UP"
				restore_failed=1
			fi
		elif interface_is_up "$iface"; then
			color_print "${RED}[RESTORE FAIL]${NC} $iface is not DOWN"
			restore_failed=1
		fi
	done < "$SNAPSHOT_FILE"

	if [ "$restore_failed" -eq 0 ]; then
		color_print "${GREEN}[RESTORE PASS]${NC} Original interface state restored"
		return 0
	fi
	return 1
}

emit_mus_result() {
	printf 'MUS_RESULT_V1|case=%s|test=%s|restore=%s|passed=%s|failed=%s|skipped=%s\n' \
		"$TEST_TO_RUN" "$TEST_STATUS" "$RESTORE_STATUS" \
		"$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}

finalize_run() {
	local requested_exit=$1
	local final_exit=$requested_exit
	local should_restore=0

	FINALIZED=1
	trap - EXIT HUP INT TERM

	if [ "$INTERRUPTED" -eq 1 ]; then
		TEST_STATUS="ERROR"
		final_exit=2
	elif [ "$requested_exit" -eq 2 ] || [ "$requested_exit" -eq 4 ]; then
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
			if restore_dut_state; then
				RESTORE_STATUS="PASS"
			else
				RESTORE_STATUS="FAIL"
				final_exit=3
			fi
		fi
	fi

	rm -f "$SNAPSHOT_FILE"
	emit_mus_result
	exit "$final_exit"
}

on_exit() {
	local exit_code=$?
	if [ "$FINALIZED" -eq 0 ]; then
		finalize_run "$exit_code"
	fi
}

on_signal() {
	INTERRUPTED=1
	exit 2
}

# Test 1: Interface bring-up creates proc entries
test_interface_bringup() {
    info "=== Test 1: Interface Bring-Up ==="

    local first_iface=$(get_first_interface)
    local all_ifaces=$(get_ra_interfaces)

    if [ -z "$first_iface" ]; then
        fail "No ra* interfaces found in /sys/class/net/"
        return
    fi

    info "First interface: $first_iface"
    info "All interfaces: $all_ifaces"

    # Bring up first interface
    ifconfig $first_iface up
    sleep 2

    local first_proc=$(get_procfs_path "$first_iface")
    if [ -d "$first_proc" ]; then
        pass "$first_iface up: $first_proc/ created"
    else
        fail "$first_iface up but $first_proc/ missing"
        return
    fi

    # Check RRM file
    if [ -f "$first_proc/SelfNeighborReportElement" ]; then
        pass "RRM SelfNeighborReportElement file exists"

        # Verify readable and has content
        local content=$(cat "$first_proc/SelfNeighborReportElement" 2>/dev/null)
        if [ -n "$content" ]; then
            pass "RRM file is readable with content"
            info "Content preview: $(echo "$content" | head -c 50)..."
        else
            fail "RRM file exists but empty or unreadable"
        fi
    else
        fail "RRM SelfNeighborReportElement file missing"
    fi

    # Check channels.json (only on main interface, not rai*)
    if ! echo "$first_iface" | grep -q '^rai'; then
        if [ -f "$first_proc/channels.json" ]; then
            pass "channels.json exists on $first_iface (main interface)"

            # Verify it's valid JSON
            if cat "$first_proc/channels.json" | grep -q '"band"'; then
                pass "channels.json has valid content"
            else
                fail "channels.json exists but content invalid"
            fi
        else
            fail "channels.json missing on $first_iface"
        fi
    else
        info "Skipping channels.json check for $first_iface (rai* not implemented)"
    fi

    # Bring up second interface if exists
    local second_iface=$(echo "$all_ifaces" | sed -n '2p')
    if [ -n "$second_iface" ]; then
        ifconfig $second_iface up
        sleep 2

        local second_proc=$(get_procfs_path "$second_iface")
        if [ -d "$second_proc" ]; then
            pass "$second_iface up: $second_proc/ created"
        else
            fail "$second_iface up but $second_proc/ missing"
        fi

        # Verify channels.json NOT on virtual interface (if not main, and not rai*)
        if [ "$second_iface" != "rax0" ] && [ "$second_iface" != "rai0" ]; then
            if ! echo "$second_iface" | grep -q '^rai'; then
                if [ ! -f "$second_proc/channels.json" ]; then
                    pass "channels.json correctly absent on $second_iface (virtual interface)"
                else
                    fail "channels.json should not exist on $second_iface"
                fi
            fi
        fi
    fi
}

# Test 2: Interface restart preserves other interfaces
test_interface_restart() {
    info "=== Test 2: Interface Restart (Down/Up) ==="

    local first_iface=$(get_first_interface)
    local second_iface=$(get_ra_interfaces | sed -n '2p')

    # Ensure interfaces are up
    for iface in $(get_ra_interfaces); do
        ifconfig $iface up 2>/dev/null
    done
    sleep 2

    # Bring down first interface
    ifconfig $first_iface down
    sleep 2

    local first_proc=$(get_procfs_path "$first_iface")
    if [ ! -d "$first_proc" ]; then
        pass "$first_iface down: $first_proc/ removed"
    else
        fail "$first_iface down but $first_proc/ still exists"
    fi

    # Check second interface still works (if exists)
    if [ -n "$second_iface" ]; then
        local second_proc=$(get_procfs_path "$second_iface")
        if [ -f "$second_proc/SelfNeighborReportElement" ]; then
            if cat "$second_proc/SelfNeighborReportElement" >/dev/null 2>&1; then
                pass "$second_iface RRM file still accessible after $first_iface down"
            else
                fail "$second_iface RRM file unreadable after $first_iface down"
            fi
        fi
    fi

    # Bring first interface back up
    ifconfig $first_iface up
    sleep 2

    if [ -d "$first_proc" ]; then
        pass "$first_iface up again: $first_proc/ recreated"
    else
        fail "$first_iface restart failed to recreate $first_proc/"
    fi

    # Verify RRM file recreated
    if [ -f "$first_proc/SelfNeighborReportElement" ]; then
        pass "RRM file recreated after $first_iface restart"
    else
        fail "RRM file missing after $first_iface restart"
    fi
}

# Test 3: Multi-interface stability
test_multi_interface_stability() {
    info "=== Test 3: Multi-Interface Stability ==="

    local all_ifaces=$(get_ra_interfaces)
    local first_iface=$(echo "$all_ifaces" | head -1)
    local second_iface=$(echo "$all_ifaces" | sed -n '2p')

    # Bring up all interfaces
    for iface in $all_ifaces; do
        ifconfig $iface up 2>/dev/null
    done
    sleep 2

    local count_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local count_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local count=$((count_mt_wifi + count_mt_wifi_1))
    local expected=$(echo "$all_ifaces" | wc -l)
    if [ "$count" -ge "$expected" ]; then
        pass "Multiple interfaces up: $count directories in procfs"
    else
        fail "Expected at least $expected interfaces, found $count"
    fi

    # Restart second interface if exists
    if [ -n "$second_iface" ]; then
        info "Restarting $second_iface..."
        ifconfig $second_iface down
        sleep 2

        local second_proc=$(get_procfs_path "$second_iface")
        if [ ! -d "$second_proc" ]; then
            pass "$second_iface down: directory removed"
        else
            fail "$second_iface directory still exists after down"
        fi

        # Verify first interface unaffected
        local first_proc=$(get_procfs_path "$first_iface")
        if [ -f "$first_proc/SelfNeighborReportElement" ]; then
            if cat "$first_proc/SelfNeighborReportElement" >/dev/null 2>&1; then
                pass "$first_iface unaffected by $second_iface restart"
            else
                fail "$first_iface affected by $second_iface restart"
            fi
        else
            fail "$first_iface missing after $second_iface down"
        fi

        # Bring second interface back up
        ifconfig $second_iface up
        sleep 2

        if [ -d "$second_proc" ]; then
            pass "$second_iface up again: directory recreated"
        else
            fail "$second_iface directory not recreated"
        fi
    fi
}

# Test 4: Rapid restart stress test
test_rapid_restart() {
    info "=== Test 4: Rapid Interface Restart (5 cycles) ==="

    local first_iface=$(get_first_interface)
    local first_proc=$(get_procfs_path "$first_iface")

    for i in 1 2 3 4 5; do
        info "Cycle $i/5..."
        ifconfig $first_iface down
        sleep 1
        ifconfig $first_iface up
        sleep 1

        if [ -f "$first_proc/SelfNeighborReportElement" ]; then
            pass "Cycle $i: RRM file present"
        else
            fail "Cycle $i: RRM file missing"
            break
        fi
    done
}

# Test 5: All interfaces restart
test_all_interfaces_restart() {
    info "=== Test 5: All Interfaces Restart ==="

    local all_ifaces=$(get_ra_interfaces)
    local iface_count=$(echo "$all_ifaces" | wc -l)

    # Bring down all interfaces
    info "Bringing down all interfaces..."
    for iface in $all_ifaces; do
        ifconfig $iface down 2>/dev/null
    done
    sleep 5

    # Check all directories removed
    local remaining_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local remaining_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local remaining=$((remaining_mt_wifi + remaining_mt_wifi_1))
    if [ "$remaining" -eq 0 ]; then
        pass "All interface directories removed"
    else
        fail "Some interface directories remain: $remaining"
    fi

    # Global directories should still exist
    if [ -d /proc/mt_wifi ]; then
        pass "/proc/mt_wifi still exists (no interfaces active)"
    else
        fail "/proc/mt_wifi removed (should persist)"
    fi
    if [ -d /proc/mt_wifi_1 ]; then
        info "/proc/mt_wifi_1 exists"
    fi

    # Bring up main interfaces (ra0, rax0, rai0) together and wait 20s
    local main_ifaces=$(get_main_interfaces)
    local virtual_ifaces=$(get_virtual_interfaces)

    if [ -n "$main_ifaces" ]; then
        info "Bringing up main interfaces (firmware load): $main_ifaces"
        for iface in $main_ifaces; do
            ifconfig $iface up 2>/dev/null
        done
        info "Waiting 20s for firmware initialization..."
        sleep 20
    fi

    # Bring up virtual interfaces
    if [ -n "$virtual_ifaces" ]; then
        info "Bringing up virtual interfaces: $virtual_ifaces"
        for iface in $virtual_ifaces; do
            ifconfig $iface up 2>/dev/null
        done
        sleep 2
    fi

    local restored_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local restored_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local restored=$((restored_mt_wifi + restored_mt_wifi_1))
    if [ "$restored" -ge "$iface_count" ]; then
        pass "All interfaces restored: $restored directories"
    else
        fail "Not all interfaces restored: expected $iface_count, got $restored"
    fi
}

# Test 6: wifi reload command
test_wifi_reload() {
    info "=== Test 6: wifi reload Command ==="

    # Check if wifi command exists
    if ! command -v wifi >/dev/null 2>&1; then
        skip "wifi command not found; reload test is not applicable"
        return
    fi

    local first_iface=$(get_first_interface)
    local first_proc=$(get_procfs_path "$first_iface")

    # Capture interface state before reload
    local before_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local before_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local before_count=$((before_mt_wifi + before_mt_wifi_1))
    info "Interfaces before reload: $before_count"

    # Execute wifi reload
    info "Executing: wifi reload (wait 20s)..."
    wifi reload >/dev/null 2>&1
    sleep 20

    # Check interfaces recreated
    local after_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local after_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local after_count=$((after_mt_wifi + after_mt_wifi_1))
    if [ "$after_count" -ge "$before_count" ]; then
        pass "wifi reload: interfaces restored ($after_count)"
    else
        fail "wifi reload: interface count decreased ($before_count -> $after_count)"
    fi

    # Verify channels.json on main interface (skip for rai*)
    if ! echo "$first_iface" | grep -q '^rai'; then
        if [ -f "$first_proc/channels.json" ]; then
            pass "wifi reload: channels.json present on $first_iface"
        else
            fail "wifi reload: channels.json missing on $first_iface"
        fi
    fi

    # Verify RRM files
    if [ -f "$first_proc/SelfNeighborReportElement" ]; then
        pass "wifi reload: RRM file present on $first_iface"
    else
        fail "wifi reload: RRM file missing on $first_iface"
    fi
}

# Test 7: wifi restart command
test_wifi_restart() {
    info "=== Test 7: wifi restart Command ==="

    # Check if wifi command exists
    if ! command -v wifi >/dev/null 2>&1; then
        skip "wifi command not found; restart test is not applicable"
        return
    fi

    local first_iface=$(get_first_interface)
    local first_proc=$(get_procfs_path "$first_iface")

    # Capture interface state before restart
    local before_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local before_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local before_count=$((before_mt_wifi + before_mt_wifi_1))
    info "Interfaces before restart: $before_count"

    # Execute wifi restart
    info "Executing: wifi restart (wait 20s)..."
    wifi restart >/dev/null 2>&1
    sleep 20

    # Check interfaces recreated
    local after_mt_wifi=$(ls -1d /proc/mt_wifi/ra* 2>/dev/null | wc -l)
    local after_mt_wifi_1=$(ls -1d /proc/mt_wifi_1/rai* 2>/dev/null | wc -l)
    local after_count=$((after_mt_wifi + after_mt_wifi_1))
    if [ "$after_count" -ge "$before_count" ]; then
        pass "wifi restart: interfaces restored ($after_count)"
    else
        fail "wifi restart: interface count decreased ($before_count -> $after_count)"
    fi

    # Verify channels.json on main interface (skip for rai*)
    if ! echo "$first_iface" | grep -q '^rai'; then
        if [ -f "$first_proc/channels.json" ]; then
            pass "wifi restart: channels.json present on $first_iface"
        else
            fail "wifi restart: channels.json missing on $first_iface"
        fi

        # Test rapid channels.json reads (stress test)
        info "Testing multiple channels.json reads..."
        for i in 1 2 3 4 5; do
            if cat "$first_proc/channels.json" | grep -q '"band"' 2>/dev/null; then
                pass "Read $i: channels.json readable"
            else
                fail "Read $i: channels.json read failed"
                break
            fi
        done
    fi

    # Verify RRM files
    if [ -f "$first_proc/SelfNeighborReportElement" ]; then
        pass "wifi restart: RRM file present on $first_iface"
    else
        fail "wifi restart: RRM file missing on $first_iface"
    fi
}

# Run specific test by number
run_test() {
    local test_num=$1
    case $test_num in
        1) test_interface_bringup ;;
        2) test_interface_restart ;;
        3) test_multi_interface_stability ;;
        4) test_rapid_restart ;;
        5) test_all_interfaces_restart ;;
        6) test_wifi_reload ;;
        7) test_wifi_restart ;;
        *) color_print "${RED}ERROR: Invalid test number: $test_num${NC}"; usage ;;
    esac
}

# Main execution
main() {
    # Parse the portable MUS contract command line.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t)
                shift
                [ "$#" -gt 0 ] || usage 4
                TEST_TO_RUN="$1"
                ;;
            -a) TEST_TO_RUN="all" ;;
            -l) list_tests ;;
            -h) usage 0 ;;
            --restore-mode)
                shift
                [ "$#" -gt 0 ] || usage 4
                RESTORE_MODE="$1"
                ;;
            --restore-mode=*) RESTORE_MODE=${1#*=} ;;
            *)
                color_print "${RED}ERROR: Unknown option: $1${NC}"
                usage 4
                ;;
        esac
        shift
    done

    case "$RESTORE_MODE" in
        always|on-success|never) ;;
        *)
            color_print "${RED}ERROR: Invalid restore mode: $RESTORE_MODE${NC}"
            usage 4
            ;;
    esac

    trap on_exit EXIT
    trap on_signal HUP INT TERM

    info "WiFi Restart Procfs Verification"
    info "================================="

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        color_print "${RED}ERROR: Must run as root${NC}"
        exit 2
    fi

    # Check if driver loaded
    if [ ! -d /proc/mt_wifi ] && [ ! -d /proc/mt_wifi_1 ]; then
        color_print "${RED}ERROR: /proc/mt_wifi and /proc/mt_wifi_1 not found - is mt_wifi driver loaded?${NC}"
        exit 2
    fi

    # Check if interfaces exist
    local all_ifaces=$(get_ra_interfaces)
    if [ -z "$all_ifaces" ]; then
        color_print "${RED}ERROR: No ra* interfaces found in /sys/class/net/${NC}"
        exit 2
    fi

    if ! snapshot_dut_state; then
        color_print "${RED}ERROR: Failed to snapshot interface state${NC}"
        exit 2
    fi

    info "Driver detected, starting tests..."
    info "Detected interfaces: $all_ifaces"
    echo ""

    # Execute tests based on user selection
    if [ "$TEST_TO_RUN" = "all" ]; then
        # Run all tests
        for i in 1 2 3 4 5 6 7; do
            run_test $i
            echo ""
        done
    else
        # Validate and run specific test
        if [ "$TEST_TO_RUN" -ge 1 ] 2>/dev/null && [ "$TEST_TO_RUN" -le 7 ] 2>/dev/null; then
            run_test "$TEST_TO_RUN"
            echo ""
        else
            color_print "${RED}ERROR: Test number must be 1-7${NC}"
            exit 4
        fi
    fi

    # Summary
    info "========================================"
    info "Test Summary:"
    info "  PASSED: $PASS_COUNT"
    info "  FAILED: $FAIL_COUNT"
    info "  Total:  $((PASS_COUNT + FAIL_COUNT))"
    info "========================================"

    if [ "$FAIL_COUNT" -eq 0 ] && [ "$SKIP_COUNT" -eq 0 ]; then
        color_print "${GREEN}All tests passed!${NC}"
    elif [ "$SKIP_COUNT" -gt 0 ] && [ "$FAIL_COUNT" -eq 0 ]; then
        color_print "${YELLOW}$SKIP_COUNT test(s) skipped.${NC}"
    else
        color_print "${RED}$FAIL_COUNT test(s) failed!${NC}"
    fi

    finalize_run 0
}

main "$@"
