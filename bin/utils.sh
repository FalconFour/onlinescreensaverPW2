#!/bin/sh
##############################################################################
# Essential utility functions for Kindle scheduler
##############################################################################

##############################################################################
# Checks if userstore (FAT partition) is safe to write to
# Returns 0 if safe, 1 if not safe (USB mass storage active)

is_userstore_available () {
	local AVAILABLE=$(lipc-get-prop com.lab126.volumd userstoreIsAvailable 2>/dev/null)
	if [ "$AVAILABLE" = "1" ]; then
		return 0  # Safe to write
	else
		return 1  # Not safe - USB mass storage active or other issue
	fi
}

##############################################################################
# Flushes temporary logs from RAM to FAT partition when safe
# Only operates when userstore is available

flush_temp_logs () {
	local TEMP_LOG="/tmp/onlinescreensaver_new.log"
	
	# Skip if logging disabled or no LOGFILE set
	if [ "x1" != "x$LOGGING" ] || [ -z "$LOGFILE" ] || [ "$LOGFILE" = "stdout" ] || [ "$LOGFILE" = "/dev/stdout" ]; then
		return
	fi
	
	# Skip if no temp log exists
	if [ ! -f "$TEMP_LOG" ]; then
		return
	fi
	
	# Skip if userstore not available
	if ! is_userstore_available; then
		return
	fi
	
	# Ensure log directory exists
	mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
	
	# Append temp log to main log file and remove temp
	cat "$TEMP_LOG" >> "$LOGFILE" 2>/dev/null && rm "$TEMP_LOG" 2>/dev/null
}

##############################################################################
# Safe logging function that writes to RAM and conditionally flushes to FAT
# Replaces the original logger() function

logger () {
	MSG=$1
	local TEMP_LOG="/tmp/onlinescreensaver_new.log"
	
	# do nothing if logging is not enabled
	if [ "x1" != "x$LOGGING" ]; then
		return
	fi

	# if no logfile is specified, set a default
	if [ -z "$LOGFILE" ]; then
		LOGFILE=stdout
	fi
	
	# Handle stdout/stderr directly (no RAM caching needed)
	if [ "$LOGFILE" = "stdout" ] || [ "$LOGFILE" = "/dev/stdout" ] || [ "$LOGFILE" = "/dev/stderr" ]; then
		echo `date`: $MSG >> $LOGFILE
		return
	fi
	
	# Write to RAM-based temp log
	echo `date`: $MSG >> "$TEMP_LOG"
	
	# Attempt to flush to FAT if safe (non-blocking)
	flush_temp_logs
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