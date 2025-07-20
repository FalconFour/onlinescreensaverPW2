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
# Sets RTC wakeup using absolute time - more reliable than relative time
# arguments: $1 - time in seconds from now

set_rtc_wakeup_absolute () {
	WAKEUP_DELAY=$1
	CURRENT_TIME=$(currentTime)
	WAKEUP_TIME=$(( $CURRENT_TIME + $WAKEUP_DELAY ))
	
	logger "Setting RTC wakeup in $WAKEUP_DELAY seconds (absolute time: $WAKEUP_TIME)"
	
	# Clear any existing alarm
	echo 0 > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
	
	# Set new wakeup time
	echo $WAKEUP_TIME > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
	
	# Verify the alarm was set correctly
	SET_ALARM=$(cat /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null)
	if [ "$SET_ALARM" = "$WAKEUP_TIME" ]; then
			logger "RTC wakeup successfully set on rtc$RTC for $WAKEUP_TIME"
			return 0
	fi

	logger "RTC$RTC rejected the alarm (wanted $WAKEUP_TIME, got $SET_ALARM)"
	return 1
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

##############################################################################
# Battery‑efficient wait function that arms RTC **and** coordinates with powerd
# arguments: $1 - time in seconds from now

wait_for_suspend () {
        WAIT_SECONDS=$1
        logger "Starting battery-efficient wait for $WAIT_SECONDS seconds"

        # Some older models have problems with the more advanced suspend logic.
        # When USE_SIMPLE_WAIT is set we still set an RTC alarm but avoid the
        # lipc‑wait loop used on newer devices.
        if [ "x$USE_SIMPLE_WAIT" = "x1" ]; then
                logger "Using simplified wait logic with RTC alarm"
                set_suspend_alarm "$WAIT_SECONDS"
                TARGET_TS=$(( $(currentTime) + WAIT_SECONDS ))
                logger "Going to sleep at $(date +%H:%M:%S)"

                # Loop in ~60s bursts so RTC wakeups break long sleeps
                while [ $(currentTime) -lt $TARGET_TS ]; do
                        NOW=$(currentTime)
                        SECS_LEFT=$(( TARGET_TS - NOW ))
                        if [ $SECS_LEFT -gt 60 ]; then
                                SLEEP_LEN=60
                        else
                                SLEEP_LEN=$SECS_LEFT
                        fi
                        sleep $SLEEP_LEN
                done

                lipc-set-prop -i com.lab126.powerd readyToSuspend 0
                logger "Woke at $(date +%H:%M:%S)"
                restore_power_settings
                return
        fi

           # Arm RTC *and* tell powerd; fall back if either fails
        if set_suspend_alarm $WAIT_SECONDS ; then
                logger "RTC alarm set, allowing device to suspend"
                logger "Going to sleep at $(date +%H:%M:%S)"

                # Enable CPU power saving
                echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null

                # Brief delay to ensure RTC is set, then allow natural suspension
                sleep 1

                # Wait for the wakeup event or timeout
                ENDTIME=$(( $(currentTime) + $WAIT_SECONDS ))
                while [ $(currentTime) -lt $ENDTIME ]; do
                        lipc-wait-event -s $(( ENDTIME - $(currentTime) )) com.lab126.powerd resuming,wakeupFromSuspend 2>/dev/null || break

                        # Check if we've reached our target time
                        if [ $(currentTime) -ge $ENDTIME ]; then
                                break
                        fi

                        sleep 0.1
                done

                lipc-set-prop -i com.lab126.powerd readyToSuspend 0

                logger "Woke at $(date +%H:%M:%S)"
                restore_power_settings
        else
                logger "RTC wakeup failed, falling back to regular sleep"
                logger "Going to sleep at $(date +%H:%M:%S)"
                sleep $WAIT_SECONDS
                logger "Woke at $(date +%H:%M:%S)"
                restore_power_settings
        fi
}

##############################################################################
# Clean RTC wakeup function for device shutdown/cleanup
clear_rtc_wakeup () {
	logger "Clearing RTC wakeup alarm"
	echo 0 > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
}

##############################################################################
# Check if device should be allowed to suspend
can_suspend () {
	# Check if we're in a state where suspension is beneficial
	DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status 2>/dev/null)
	
	case "$DEVICE_STATUS" in
		*"Active"*)
			# Device is actively being used
			return 1
			;;
		*"Screen Saver"*|*"Ready"*)
			# Device can suspend
			return 0
			;;
		*)
			# Unknown state, allow suspension to be safe
			return 0
			;;
	esac
}

##############################################################################
# Optimized power management - reduces CPU usage and allows suspension
enable_power_savings () {
        logger "Enabling power saving optimizations"
	
	# Set CPU to power save mode
	if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
		echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
		logger "CPU set to powersave mode"
	fi
	
	# Reduce CPU frequency if possible
	if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed ]; then
		MIN_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null)
		if [ -n "$MIN_FREQ" ]; then
			echo $MIN_FREQ > /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed 2>/dev/null
			logger "CPU frequency reduced to minimum: $MIN_FREQ"
		fi
	fi
}

restore_power_settings () {
        logger "Restoring normal power settings"
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
                echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
        fi
}

##############################################################################
# Legacy functions kept for compatibility but improved

# Original wait_for function - improved for better power management
wait_for () {
	wait_for_suspend $1
}

# Improved version of the original wait_for_fixed
wait_for_fixed () {
	logger "wait_for_fixed() started with power optimizations"
	
	enable_power_savings
	
	# Use our improved suspend-friendly wait
	wait_for_suspend $1
	
	logger "wait_for_fixed() finished"
}

# runs when in the readyToSuspend state - improved version
# set_rtc_wakeup() {
# 	logger "Setting rtcWakeup property to $1 seconds"
# 	lipc-set-prop -i com.lab126.powerd rtcWakeup $1 2>/dev/null
	
# 	# Also set direct RTC alarm as backup
# 	set_rtc_wakeup_absolute $1
# }

##############################################################################
# Cleanup function for graceful shutdown
cleanup_and_exit () {
	logger "Performing cleanup before exit"
	clear_rtc_wakeup
	exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup_and_exit TERM INT QUIT