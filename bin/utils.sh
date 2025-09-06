#!/bin/sh
##############################################################################
# Essential utility functions for Kindle scheduler
##############################################################################

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