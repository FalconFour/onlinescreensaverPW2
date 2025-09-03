#!/bin/sh
##############################################################################
# Battery-efficient utility functions for Kindle scheduler
##############################################################################

##############################################################################
# Device specific defaults
##############################################################################

# Some older models such as the Kindle Paperwhite 2 appear to have issues with
# the advanced suspend logic used in the wait_for_suspend function.  On these
# devices the scheduler would occasionally freeze after running for an hour or
# so.  We try to detect the model and fall back to a simpler waiting logic
# when necessary.

if [ -z "$USE_SIMPLE_WAIT" ]; then
    if [ -f /etc/prettyName ] && grep -qi "Paperwhite.*2" /etc/prettyName ; then
        USE_SIMPLE_WAIT=1
    else
        USE_SIMPLE_WAIT=0
    fi
fi
export USE_SIMPLE_WAIT
logger "USE_SIMPLE_WAIT is set to $USE_SIMPLE_WAIT"

# Removed HOLD_ACTIVE - now using Screen Saver state management
NA_STREAK_FILE=/var/local/system/onlinescreensaver_na_streak

# If we accidentally end up Active, push back to Screen Saver
ensure_screensaver_if_active () {
    case "$(/usr/bin/powerd_test -s 2>/dev/null)" in *"Active"*) /usr/bin/powerd_test -p 2>/dev/null || true;; esac
}

wifi_cm_state () { lipc-get-prop com.lab126.wifid cmState 2>/dev/null || echo NA; }
wifi_enabled ()  { lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null || echo 0; }

log_wifi_diag () {
    local s en iscon ip ifline
    s=$(wifi_cm_state); en=$(wifi_enabled)
    iscon=$(lipc-get-prop com.lab126.wifid isConnected 2>/dev/null || echo NA)
    ip=$(ip addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | head -n1)
    ifline=$(ip link show wlan0 2>/dev/null | head -n1)
    logger "WiFi diag: cmState=$s enabled=$en isConnected=$iscon ip=${ip:-none} if=${ifline:-none}"
}

restart_wifi_services () {
    for svc in wifid wlancond netwatchd; do
        if command -v initctl >/dev/null 2>&1; then initctl restart "$svc" 2>/dev/null || true; fi
        if [ -x "/etc/init.d/$svc" ]; then /etc/init.d/$svc restart 2>/dev/null || true; fi
    done
}

recover_wifi_from_NA () {
    logger "WiFi cmState=NA; beginning recovery"
    powerd_soft_extend
    log_wifi_diag
    # Step 1: short wait for framework to report a real state
    local t=0; while [ $t -lt 20 ]; do [ "$(wifi_cm_state)" != "NA" ] && return 0; t=$((t+1)); sleep 1; done
    logger "Recovery step1 timed out; restarting Wi‑Fi services"
    restart_wifi_services; sleep 5
    local i; for i in 1 2 3 4 5; do [ "$(wifi_cm_state)" != "NA" ] && return 0; sleep 2; done
    logger "Recovery step2 failed; toggling wirelessEnable"
    lipc-set-prop com.lab126.cmd wirelessEnable 0; sleep 2; lipc-set-prop com.lab126.cmd wirelessEnable 1
    logger "Waiting 12 seconds after toggle"; sleep 12
    [ "$(wifi_cm_state)" != "NA" ] && return 0
    logger "Recovery failed: cmState still NA"; return 1
}

# Track NA streak across runs
na_streak_inc () { local n=0; [ -f "$NA_STREAK_FILE" ] && n=$(cat "$NA_STREAK_FILE" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$NA_STREAK_FILE"; echo $n; }
na_streak_reset () { echo 0 > "$NA_STREAK_FILE"; }
na_streak_read () { [ -f "$NA_STREAK_FILE" ] && cat "$NA_STREAK_FILE" 2>/dev/null || echo 0; }

##############################################################################
# Logs a message to a log file (or to console if argument is /dev/stdout)

logger () {
	MSG=$1
	
	# do nothing if logging is not enabled
	if [ "x1" != "x$LOGGING" ]; then
		return
	fi

	# if no logfile is specified, set a default
	if [ -z $LOGFILE ]; then
		LOGFILE=stdout
	fi

	echo `date`: $MSG >> $LOGFILE
}

##############################################################################
# Retrieves the current time in seconds

currentTime () {
	date +%s
}

##############################################################################
# Sets RTC wakeup using relative time
# arguments: $1 - time in seconds from now

set_rtc_wakeup_relative () {
	local SECONDS_FROM_NOW=$1
	
	# Set new wakeup time (rtcWakeup expects relative seconds)
	lipc-set-prop -i com.lab126.powerd rtcWakeup $SECONDS_FROM_NOW
	logger "RTC wakeup set for $SECONDS_FROM_NOW seconds from now ($(date -d @$(( $(currentTime) + $SECONDS_FROM_NOW )) +%H:%M:%S))"
	return 0
}

# runs when the system displays the screensaver
log_ScreenSaver()
{
	logger "Screen Saver State"
}

# runs when the RTC wakes the system up
log_Wakeup()
{
	logger "Wakeup State"
}

# utils.sh
set_suspend_alarm () {
    SECS=$1

    # Tell powerd we have finished our work and it may suspend now
    lipc-set-prop -i com.lab126.powerd readyToSuspend 1

    if [ $SECS -ge 300 ]; then
        # ≥ 5 min → let powerd mirror the exact value
        lipc-set-prop -i com.lab126.powerd rtcWakeup $SECS
    else
        # 60 – 299 s → satisfy powerd with the *minimum* accepted delta
        lipc-set-prop -i com.lab126.powerd rtcWakeup 300
    fi

    # Always program the hardware RTC ourselves as the primary alarm
    set_rtc_wakeup_absolute $SECS
}
