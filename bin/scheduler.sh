#!/bin/sh
#
##############################################################################
#
# Battery-efficient weather screensaver scheduler for Kindle
#
# Features:
#   - updates on schedule while allowing device suspension
#   - uses RTC wakeup to minimize battery drain
#   - only stays awake during actual updates
#   - handles screensaver and ready states efficiently
#
##############################################################################

# change to directory of this script
cd "$(dirname "$0")"

# load configuration
if [ -e "config.sh" ]; then
        source ./config.sh
else
        # set default values
        INTERVAL=240
        RTC=0
fi

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit 1
fi

###############################################################################


##############################################################################

# Calculate seconds until next update dynamically from current time and schedule
get_seconds_until_next_update () {
    local CURRENT_TIME=$(currentTime)
    local CURRENT_HOUR=$(date +%H | sed 's/^0*//' | sed 's/^$/0/')
    local CURRENT_MINUTE=$(date +%M | sed 's/^0*//' | sed 's/^$/0/')
    local CURRENT_SECOND=$(date +%S | sed 's/^0*//' | sed 's/^$/0/')
    
    local CURRENT_MINUTES=$(( CURRENT_HOUR * 60 + CURRENT_MINUTE ))
    local CURRENT_DAY_SECONDS=$(( CURRENT_HOUR * 3600 + CURRENT_MINUTE * 60 + CURRENT_SECOND ))
    
    logger "Current time: $(date +%H:%M:%S) ($CURRENT_MINUTES minutes from midnight)"
    
    # Find which schedule period we're currently in
    for schedule in $SCHEDULE; do
        read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
            $( echo " $schedule" | sed -e 's/[:,=,\,,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
        
        local START_MIN=$(( STARTHOUR * 60 + STARTMINUTE ))
        local END_MIN=$(( ENDHOUR * 60 + ENDMINUTE ))
        
        if [ $CURRENT_MINUTES -ge $START_MIN ] && [ $CURRENT_MINUTES -lt $END_MIN ]; then
            # We're in this schedule period
            logger "In schedule period: $STARTHOUR:$(printf '%02d' $STARTMINUTE)-$ENDHOUR:$(printf '%02d' $ENDMINUTE) (interval: ${INTERVAL}min)"
            
            local PERIOD_ELAPSED=$(( CURRENT_MINUTES - START_MIN ))
            local COMPLETE_INTERVALS=$(( PERIOD_ELAPSED / INTERVAL ))
            local NEXT_UPDATE_MIN=$(( START_MIN + (COMPLETE_INTERVALS + 1) * INTERVAL ))
            
            # If next update would be past the end of this period, use the end time
            if [ $NEXT_UPDATE_MIN -ge $END_MIN ]; then
                NEXT_UPDATE_MIN=$END_MIN
            fi
            
            local NEXT_UPDATE_SECONDS=$(( NEXT_UPDATE_MIN * 60 ))
            local WAIT_SECONDS=$(( NEXT_UPDATE_SECONDS - CURRENT_DAY_SECONDS ))
            
            # Minimum 5 minutes between updates
            [ $WAIT_SECONDS -lt 300 ] && WAIT_SECONDS=300
            
            logger "Next update in $WAIT_SECONDS seconds"
            echo $WAIT_SECONDS
            return
        fi
    done
    
    # Not in any defined period - find next period start
    local NEXT_START=-1
    for schedule in $SCHEDULE; do
        read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
            $( echo " $schedule" | sed -e 's/[:,=,\,,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
        
        local START_MIN=$(( STARTHOUR * 60 + STARTMINUTE ))
        
        if [ $START_MIN -gt $CURRENT_MINUTES ]; then
            if [ $NEXT_START -eq -1 ] || [ $START_MIN -lt $NEXT_START ]; then
                NEXT_START=$START_MIN
            fi
        fi
    done
    
    # If no period found after current time, use tomorrow's first period
    if [ $NEXT_START -eq -1 ]; then
        # Find first period of the day
        for schedule in $SCHEDULE; do
            read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
                $( echo " $schedule" | sed -e 's/[:,=,\,,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
            
            local START_MIN=$(( STARTHOUR * 60 + STARTMINUTE ))
            
            if [ $NEXT_START -eq -1 ] || [ $START_MIN -lt $NEXT_START ]; then
                NEXT_START=$START_MIN
            fi
        done
        
        # Add 24 hours for tomorrow
        NEXT_START=$(( NEXT_START + 24*60 ))
    fi
    
    local NEXT_START_SECONDS=$(( NEXT_START * 60 ))
    local WAIT_SECONDS=$(( NEXT_START_SECONDS - CURRENT_DAY_SECONDS ))
    
    # Handle day wrap-around
    if [ $WAIT_SECONDS -le 0 ]; then
        WAIT_SECONDS=$(( WAIT_SECONDS + 24*3600 ))
    fi
    
    # Minimum 5 minutes between updates
    [ $WAIT_SECONDS -lt 300 ] && WAIT_SECONDS=300
    
    logger "Next update in $WAIT_SECONDS seconds (at next period start)"
    echo $WAIT_SECONDS
}


##############################################################################

# perform update with timeout protection (Kindle-compatible)
do_update_cycle () {
	logger "Starting update cycle"
	
        # Check initial WiFi status and log it
        WIFI_STATUS=`lipc-get-prop com.lab126.cmd wirelessEnable`
        logger "Initial WiFi status: $WIFI_STATUS"

        # Enable wireless if it is currently off
        if [ 0 -eq "$WIFI_STATUS" ]; then
                logger "WiFi is off, turning it on now"
                lipc-set-prop com.lab126.cmd wirelessEnable 1

                # Give WiFi more time to initialize after turning on
                logger "Waiting 10 seconds for WiFi to initialize..."
                sleep 10
        else
                logger "WiFi was already enabled"
        fi

        # Check WiFi connection status
        WIFI_CONNECTION=`lipc-get-prop com.lab126.wifid cmState`
        logger "WiFi state after groggy toggle: $WIFI_CONNECTION"

	# Run the update in background
	sh ./update.sh &
	UPDATE_PID=$!
	
	# Wait for update to complete with timeout
	TIMEOUT=20  # 20 seconds
	ELAPSED=0
	
	while [ $ELAPSED -lt $TIMEOUT ]; do
		if ! kill -0 $UPDATE_PID 2>/dev/null; then
			# Process has finished
			wait $UPDATE_PID
			UPDATE_RESULT=$?
			if [ $UPDATE_RESULT -eq 0 ]; then
				logger "Update completed successfully in $ELAPSED seconds"
			else
				logger "Update failed with exit code $UPDATE_RESULT after $ELAPSED seconds"
			fi
			return
		fi
		
		sleep 5
		ELAPSED=$(( $ELAPSED + 5 ))
	done
	
	# Timeout reached - kill the update process
	logger "Update timed out after $TIMEOUT seconds, killing process $UPDATE_PID"
	kill $UPDATE_PID 2>/dev/null
	sleep 2
	kill -9 $UPDATE_PID 2>/dev/null  # Force kill if still running
	
	logger "Update cycle finished (timed out)"
}

##############################################################################

# Main event-driven loop
logger "Starting event-driven scheduler - waiting for powerd events"
lipc-wait-event -m com.lab126.powerd goingToScreenSaver,wakeupFromSuspend,readyToSuspend | while read event; do
    logger "Received event: $event"
    
    DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status)
    logger "Device status: $DEVICE_STATUS"

    case "$event" in
        goingToScreenSaver*)
            logger "Going to screensaver - performing scheduled update"
            do_update_cycle
            ;;
        wakeupFromSuspend*)
            logger "Waking from suspend - waiting 2 seconds for system, then updating"
            sleep 2
            do_update_cycle
            ;;
        readyToSuspend*)
            logger "Ready to suspend - setting RTC wakeup timer"
            NEXT_UPDATE_SECONDS=$(get_seconds_until_next_update)
            logger "Next update in $NEXT_UPDATE_SECONDS seconds"
            set_rtc_wakeup_relative $NEXT_UPDATE_SECONDS
            ;;
        *)
            logger "Unknown event: $event"
            ;;
    esac
    
    logger "Ensuring WiFi is turned off..."
    lipc-set-prop com.lab126.cmd wirelessEnable 0
done
