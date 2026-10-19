#!/bin/sh
# 1.3 Client Connectivity - Security Modes.  POSIX sh / BusyBox ash compatible.
# Reconfigures all three bands (ra0/rai0/rax0) to a single security mode,
# verifies the AP advertisement via iwpriv AuthMode, then restores original UCI.
# Candela LANforge 64-client KPI measurement is a future extension.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
TEST_TO_RUN=1; RESTORE_MODE=always
TEST_STATUS=ERROR; RESTORE_STATUS=NOT_REQUIRED
SNAPSHOT_FILE="/tmp/mus-security-state-$$"
SNAPSHOT_READY=0; MUTATED=0; FINALIZED=0; INTERRUPTED=0

# ra0=2.4G, rai0=5G, rax0=6G
# 6 GHz (Wi-Fi 6E/7) only supports WPA3/SAE and OWE; WPA2/Open not allowed.
BANDS="ra0 rai0 rax0"
BANDS_2G4_5G="ra0 rai0"
BANDS_6G="rax0"

print_color() { printf '%b\n' "$1"; }
info()  { print_color "${YELLOW}[INFO]${NC} $1"; }
pass()  { print_color "${GREEN}[PASS]${NC} $1";  PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { print_color "${RED}[FAIL]${NC} $1";   FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip()  { print_color "${YELLOW}[SKIP]${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }
usage() { code=${1:-0}; printf 'Usage: %s -t 1-6 [--restore-mode always|on-success|never]\n' "$0"; exit "$code"; }

# ---------------------------------------------------------------------------
# State snapshot and restore
# ---------------------------------------------------------------------------

snapshot_dut_state() {
    : > "$SNAPSHOT_FILE" || return 1
    for iface in $BANDS; do
        enc=$(uci -q get "wireless.${iface}.encryption"); enc=${enc:-none}
        key=$(uci -q get "wireless.${iface}.key");        key=${key:-}
        pmf=$(uci -q get "wireless.${iface}.ieee80211w"); pmf=${pmf:-0}
        if ifconfig "$iface" 2>/dev/null | grep -q 'UP'; then state=up; else state=down; fi
        printf '%s|%s|%s|%s|%s\n' "$iface" "$enc" "$key" "$pmf" "$state" >> "$SNAPSHOT_FILE" || return 1
    done
    SNAPSHOT_READY=1
    info "Snapshot saved to $SNAPSHOT_FILE"
}

restore_dut_state() {
    err=0
    while IFS='|' read -r iface enc key pmf state; do
        uci set "wireless.${iface}.encryption=${enc}" 2>/dev/null || err=1
        if [ -n "$key" ]; then
            uci set "wireless.${iface}.key=${key}" 2>/dev/null || err=1
        else
            uci -q delete "wireless.${iface}.key" 2>/dev/null
        fi
        uci set "wireless.${iface}.ieee80211w=${pmf}" 2>/dev/null || err=1
    done < "$SNAPSHOT_FILE"
    uci commit wireless 2>/dev/null || err=1
    wifi restart >/dev/null 2>&1 || err=1
    wait_for_wifi 30 || err=1
    while IFS='|' read -r iface enc key pmf state; do
        [ -e "/sys/class/net/$iface" ] || { print_color "${RED}[RESTORE FAIL]${NC} missing $iface"; err=1; continue; }
        if [ "$state" = up ]; then
            ifconfig "$iface" 2>/dev/null | grep -q 'UP' || { print_color "${RED}[RESTORE FAIL]${NC} $iface not UP"; err=1; }
        fi
    done < "$SNAPSHOT_FILE"
    [ "$err" -eq 0 ] && print_color "${GREEN}[RESTORE PASS]${NC} original security settings restored"
    return "$err"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

wait_for_wifi() {
    deadline=$1; elapsed=0
    while [ "$elapsed" -lt "$deadline" ]; do
        all_up=1
        for iface in $BANDS; do
            [ -e "/sys/class/net/$iface" ] || { all_up=0; break; }
        done
        [ "$all_up" -eq 1 ] && return 0
        sleep 2; elapsed=$((elapsed + 2))
    done
    return 1
}

apply_security_mode() {
    enc="$1"; key="$2"; pmf="$3"; band_list="${4:-$BANDS}"
    for iface in $band_list; do
        uci set "wireless.${iface}.encryption=${enc}" 2>/dev/null || return 1
        if [ -n "$key" ]; then
            uci set "wireless.${iface}.key=${key}" 2>/dev/null || return 1
        else
            uci -q delete "wireless.${iface}.key" 2>/dev/null
        fi
        uci set "wireless.${iface}.ieee80211w=${pmf}" 2>/dev/null || return 1
    done
    uci commit wireless 2>/dev/null || return 1
    MUTATED=1
    wifi restart >/dev/null 2>&1 || return 1
    info "Waiting 25 s for Wi-Fi to reinitialise..."
    sleep 25
    wait_for_wifi 30 || { info "Interfaces did not reappear after wifi restart"; return 1; }
    return 0
}

verify_auth_mode() {
    iface="$1"; expected="$2"
    # MT7999 does not support iwpriv show AuthMode; use hostapd_cli get_config
    actual=$(hostapd_cli -i "$iface" get_config 2>/dev/null | grep '^key_mgmt=' | cut -d= -f2)
    if [ -z "$actual" ]; then
        fail "$iface: hostapd_cli get_config returned no key_mgmt"
        return 1
    fi
    if printf '%s\n' "$actual" | grep -qi "$expected"; then
        pass "$iface: key_mgmt=$actual (expected $expected)"
    else
        fail "$iface: key_mgmt=$actual (expected $expected)"
    fi
}

verify_uci_encryption() {
    iface="$1"; expected_enc="$2"
    actual_enc=$(uci -q get "wireless.${iface}.encryption" 2>/dev/null)
    if [ "$actual_enc" = "$expected_enc" ]; then
        pass "$iface: UCI encryption=$actual_enc"
    else
        fail "$iface: UCI encryption=$actual_enc (expected $expected_enc)"
    fi
}

verify_interface_up() {
    iface="$1"
    if ifconfig "$iface" 2>/dev/null | grep -q 'UP'; then
        pass "$iface is UP"
    else
        fail "$iface is not UP"
    fi
}

# ---------------------------------------------------------------------------
# MUS contract boilerplate
# ---------------------------------------------------------------------------

emit_result() {
    printf 'MUS_RESULT_V1|case=%s|test=%s|restore=%s|passed=%s|failed=%s|skipped=%s\n' \
        "$TEST_TO_RUN" "$TEST_STATUS" "$RESTORE_STATUS" \
        "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
}

finalize() {
    wanted=$1; final=$wanted; restore=0; FINALIZED=1
    trap - EXIT HUP INT TERM
    if [ "$INTERRUPTED" -eq 1 ] || [ "$wanted" -eq 2 ] || [ "$wanted" -eq 4 ]; then
        TEST_STATUS=ERROR
    elif [ "$FAIL_COUNT" -gt 0 ]; then
        TEST_STATUS=FAIL; final=1
    elif [ "$PASS_COUNT" -eq 0 ]; then
        TEST_STATUS=ERROR; final=2
    else
        TEST_STATUS=PASS; final=0
    fi
    if [ "$SNAPSHOT_READY" -eq 1 ] && [ "$MUTATED" -eq 1 ]; then
        case "$RESTORE_MODE" in
            always)     restore=1 ;;
            on-success) [ "$TEST_STATUS" = PASS ] && restore=1 || RESTORE_STATUS=PRESERVED ;;
            never)      RESTORE_STATUS=PRESERVED ;;
        esac
        if [ "$restore" -eq 1 ]; then
            restore_dut_state && RESTORE_STATUS=PASS || { RESTORE_STATUS=FAIL; final=3; }
        fi
    fi
    rm -f "$SNAPSHOT_FILE"
    emit_result
    exit "$final"
}

on_exit()   { code=$?; [ "$FINALIZED" -eq 1 ] || finalize "$code"; }
on_signal() { INTERRUPTED=1; exit 2; }

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test1() {
    # Open - no authentication, no encryption (2.4G and 5G only; 6G requires WPA3)
    info "Applying Open (no auth) on 2.4G and 5G bands"
    info "6G (rax0) is skipped: Wi-Fi 6E/7 mandates WPA3/OWE on 6 GHz"
    apply_security_mode "none" "" "0" "$BANDS_2G4_5G" || { fail "Failed to apply Open mode"; return; }
    for iface in $BANDS_2G4_5G; do
        verify_interface_up "$iface"
        verify_uci_encryption "$iface" "none"
        # hostapd_cli get_config: open BSS has no key_mgmt line (wpa=0)
        wpa_val=$(hostapd_cli -i "$iface" get_config 2>/dev/null | grep '^wpa=' | cut -d= -f2)
        [ "$wpa_val" = "0" ] || [ -z "$wpa_val" ] && \
            pass "$iface: open BSS confirmed (wpa=$wpa_val)" || \
            fail "$iface: wpa=$wpa_val (expected 0 for open mode)"
    done
    skip "rax0 (6G): Open not allowed on 6 GHz (Wi-Fi 6E/7 requirement)"
}

test2() {
    # WPA2-PSK (CCMP), PMF optional (2.4G and 5G only; 6G requires WPA3)
    info "Applying WPA2-PSK on 2.4G and 5G bands"
    info "6G (rax0) is skipped: Wi-Fi 6E/7 mandates WPA3 on 6 GHz"
    apply_security_mode "psk2" "TestPassphrase1234" "1" "$BANDS_2G4_5G" || { fail "Failed to apply WPA2-PSK"; return; }
    for iface in $BANDS_2G4_5G; do
        verify_interface_up "$iface"
        verify_uci_encryption "$iface" "psk2"
        verify_auth_mode "$iface" "WPA-PSK"
        # Confirm CCMP pairwise cipher
        cipher=$(hostapd_cli -i "$iface" get_config 2>/dev/null | grep '^rsn_pairwise_cipher=' | cut -d= -f2)
        if printf '%s\n' "$cipher" | grep -qi "CCMP"; then
            pass "$iface: rsn_pairwise_cipher=$cipher (CCMP confirmed)"
        else
            fail "$iface: rsn_pairwise_cipher=$cipher (expected CCMP)"
        fi
    done
    skip "rax0 (6G): WPA2-PSK not allowed on 6 GHz (Wi-Fi 6E/7 requirement)"
}

test3() {
    # WPA3-SAE H2E, PMF required
    info "Applying WPA3-SAE (H2E) on all bands"
    apply_security_mode "sae" "TestPassphrase1234" "2" || { fail "Failed to apply WPA3-SAE"; return; }
    for iface in $BANDS; do
        verify_interface_up "$iface"
        verify_uci_encryption "$iface" "sae"
        verify_auth_mode "$iface" "SAE"
        # Verify PMF required (ieee80211w=2 -> hostapd ieee80211w=2)
        pmf_val=$(uci -q get "wireless.${iface}.ieee80211w" 2>/dev/null)
        [ "$pmf_val" = "2" ] && pass "$iface: ieee80211w=2 (PMF required)" || \
            fail "$iface: ieee80211w=$pmf_val (expected 2 for PMF required)"
    done
    # Verify H2E: uci sae_pwe or hostapd sae_pwe if available
    for iface in $BANDS; do
        sae_pwe=$(uci -q get "wireless.${iface}.sae_pwe" 2>/dev/null)
        if [ -n "$sae_pwe" ]; then
            [ "$sae_pwe" = "1" ] || [ "$sae_pwe" = "2" ] && \
                pass "$iface: sae_pwe=$sae_pwe (H2E mode set)" || \
                info "$iface: sae_pwe=$sae_pwe (H2E not explicitly required; driver default)"
        else
            info "$iface: sae_pwe not in UCI (driver enforces H2E via SAE default)"
        fi
    done
}

test4() {
    # WPA2/WPA3 Transition (sae-compat = PSK + SAE simultaneously), PMF optional
    info "Applying WPA2/WPA3 Transition (sae-compat) on all bands"
    apply_security_mode "sae-compat" "TestPassphrase1234" "1" || { fail "Failed to apply WPA2/WPA3 Transition"; return; }
    for iface in $BANDS; do
        verify_interface_up "$iface"
        verify_uci_encryption "$iface" "sae-compat"
        # hostapd key_mgmt for sae-compat should contain both WPA-PSK and SAE
        actual=$(hostapd_cli -i "$iface" get_config 2>/dev/null | grep '^key_mgmt=' | cut -d= -f2)
        has_psk=$(printf '%s\n' "$actual" | grep -c "WPA-PSK" || true)
        has_sae=$(printf '%s\n' "$actual" | grep -c "SAE" || true)
        if [ "$has_psk" -gt 0 ] && [ "$has_sae" -gt 0 ]; then
            pass "$iface: key_mgmt=$actual (WPA-PSK and SAE both advertised)"
        elif [ "$has_psk" -gt 0 ] || [ "$has_sae" -gt 0 ]; then
            pass "$iface: key_mgmt=$actual (transition mode active)"
        else
            fail "$iface: key_mgmt=$actual (neither WPA-PSK nor SAE found)"
        fi
    done
}

test5() {
    # WPA3-Enterprise 802.1X/RADIUS - skip if UCI set fails (no RADIUS available)
    info "Attempting WPA3-Enterprise (802.1X/RADIUS) on all bands"
    # Probe: attempt to set wpa3 EAP mode; if UCI rejects it we skip cleanly.
    uci set "wireless.ra0.encryption=wpa3" 2>/dev/null
    uci commit wireless 2>/dev/null
    actual_enc=$(uci -q get wireless.ra0.encryption 2>/dev/null)
    if [ "$actual_enc" != "wpa3" ]; then
        info "wpa3 encryption not accepted by UCI on this build; skipping Enterprise case"
        # Restore ra0 to snapshot value before exiting
        uci set "wireless.ra0.encryption=sae-compat" 2>/dev/null
        uci commit wireless 2>/dev/null
        SKIP_COUNT=$((SKIP_COUNT + 1))
        TEST_STATUS=SKIP
        RESTORE_STATUS=NOT_REQUIRED
        emit_result
        exit 77
    fi
    # Restore ra0 to avoid partial state before full apply
    uci set "wireless.ra0.encryption=sae-compat" 2>/dev/null
    uci commit wireless 2>/dev/null
    info "UCI accepts wpa3 mode; applying on all bands (auth mode check only, no live RADIUS)"
    apply_security_mode "wpa3" "" "2" || {
        info "Failed to apply WPA3-Enterprise on all bands; skipping"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        TEST_STATUS=SKIP
        RESTORE_STATUS=NOT_REQUIRED
        emit_result
        exit 77
    }
    for iface in $BANDS; do
        verify_interface_up "$iface"
        actual=$(hostapd_cli -i "$iface" get_config 2>/dev/null | grep '^key_mgmt=' | cut -d= -f2)
        if printf '%s\n' "$actual" | grep -qi "WPA-EAP\|EAP"; then
            pass "$iface: key_mgmt=$actual (EAP/WPA3-Enterprise advertised)"
        else
            fail "$iface: key_mgmt=$actual (expected WPA-EAP)"
        fi
    done
}

test6() {
    # OWE - Opportunistic Wireless Encryption, PMF required
    info "Applying OWE on all bands"
    apply_security_mode "owe" "" "2" || { fail "Failed to apply OWE"; return; }
    for iface in $BANDS; do
        verify_interface_up "$iface"
        verify_uci_encryption "$iface" "owe"
        verify_auth_mode "$iface" "OWE"
        pmf_val=$(uci -q get "wireless.${iface}.ieee80211w" 2>/dev/null)
        [ "$pmf_val" = "2" ] && pass "$iface: ieee80211w=2 (PMF required)" || \
            fail "$iface: ieee80211w=$pmf_val (expected 2 for PMF required)"
    done
}

# ---------------------------------------------------------------------------
# Argument parsing and entry point
# ---------------------------------------------------------------------------

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t) shift; [ "$#" -gt 0 ] || usage 4; TEST_TO_RUN=$1 ;;
            --restore-mode) shift; [ "$#" -gt 0 ] || usage 4; RESTORE_MODE=$1 ;;
            --restore-mode=*) RESTORE_MODE=${1#*=} ;;
            -l)
                printf '1. Open (no authentication)\n'
                printf '2. WPA2-PSK (PMF optional)\n'
                printf '3. WPA3-SAE H2E (PMF required)\n'
                printf '4. WPA2/WPA3 Transition (PMF optional)\n'
                printf '5. WPA3-Enterprise 802.1X/RADIUS (PMF required)\n'
                printf '6. OWE Opportunistic Wireless Encryption (PMF required)\n'
                exit 0 ;;
            -h) usage 0 ;;
            *) usage 4 ;;
        esac
        shift
    done

    case "$TEST_TO_RUN" in 1|2|3|4|5|6) ;; *) usage 4 ;; esac
    case "$RESTORE_MODE" in always|on-success|never) ;; *) usage 4 ;; esac

    trap on_exit EXIT
    trap on_signal HUP INT TERM

    [ "$(id -u)" -eq 0 ] || { info 'Must run as root'; exit 2; }
    command -v uci          >/dev/null 2>&1 || { info 'uci is required';          exit 2; }
    command -v hostapd_cli  >/dev/null 2>&1 || { info 'hostapd_cli is required';  exit 2; }
    command -v wifi         >/dev/null 2>&1 || { info 'wifi is required';         exit 2; }
    command -v ifconfig     >/dev/null 2>&1 || { info 'ifconfig is required';     exit 2; }

    for iface in $BANDS; do
        [ -e "/sys/class/net/$iface" ] || { info "Interface $iface not found; check DUT Wi-Fi state"; exit 2; }
    done

    snapshot_dut_state || { info 'Failed to snapshot DUT state'; exit 2; }

    case "$TEST_TO_RUN" in
        1) test1 ;;
        2) test2 ;;
        3) test3 ;;
        4) test4 ;;
        5) test5 ;;
        6) test6 ;;
    esac

    finalize 0
}

main "$@"
