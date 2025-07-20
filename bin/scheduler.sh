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

# Log current configuration
if [ -f /etc/prettyName ]; then
    DEVICE_MODEL=$(cat /etc/prettyName)
    logger "Detected device model: $DEVICE_MODEL"
fi
logger "Scheduler starting with USE_SIMPLE_WAIT=$USE_SIMPLE_WAIT"

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit 1
fi

###############################################################################

# create a two day filling schedule
extend_schedule () {
	SCHEDULE_ONE=""
	SCHEDULE_TWO=""

	LASTENDHOUR=0
	LASTENDMINUTE=0
	LASTEND=0
	for schedule in $SCHEDULE; do
		read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE THISINTERVAL << EOF
			$( echo " $schedule" | sed -e 's/[:,=,\,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g')
EOF
		START=$(( 60*$STARTHOUR + $STARTMINUTE ))
		END=$(( 60*$ENDHOUR + $ENDMINUTE ))

		# if the previous schedule entry ended before this one starts,
		# create a filler
		if [ $LASTEND -lt $START ]; then
			SCHEDULE_ONE="$SCHEDULE_ONE $LASTENDHOUR:$LASTENDMINUTE-$STARTHOUR:$STARTMINUTE=$DEFAULTINTERVAL"
			SCHEDULE_TWO="$SCHEDULE_TWO $(($LASTENDHOUR+24)):$LASTENDMINUTE-$(($STARTHOUR+24)):$STARTMINUTE=$DEFAULTINTERVAL"
		fi
		SCHEDULE_ONE="$SCHEDULE_ONE $schedule"
		SCHEDULE_TWO="$SCHEDULE_TWO $(($STARTHOUR+24)):$STARTMINUTE-$(($ENDHOUR+24)):$ENDMINUTE=$THISINTERVAL"
		
		LASTENDHOUR=$ENDHOUR
		LASTENDMINUTE=$ENDMINUTE
		LASTEND=$END
	done

	# check that the schedule goes to midnight
	if [ $LASTEND -lt $(( 24*60 )) ]; then
		SCHEDULE_ONE="$SCHEDULE_ONE $LASTENDHOUR:$LASTENDMINUTE-24:00=$DEFAULTINTERVAL"
		SCHEDULE_TWO="$SCHEDULE_TWO $(($LASTENDHOUR+24)):$LASTENDMINUTE-48:00=$DEFAULTINTERVAL"
	fi
	
        # to handle the day overlap, append the schedule again for hours 24-48.
        SCHEDULE="$SCHEDULE_ONE $SCHEDULE_TWO"
        logger "Full two day schedule: $SCHEDULE"

        # Calculate timestamp for today's midnight
        H=$(date +%-H)
        M=$(date +%-M)
        S=$(date +%-S)
        SCHEDULE_BASE=$(( $(date +%s) - (H*3600 + M*60 + S) ))
        logger "Schedule base timestamp: $SCHEDULE_BASE"
}

##############################################################################


# Calculate epoch timestamp for next update after the given reference time
# arguments: $1 - reference UNIX timestamp
get_next_update_epoch () {
        REF_TS=$1
        REF_MIN=$(( (REF_TS - SCHEDULE_BASE) / 60 ))
        NEXT_MIN=-1

        logger "Computing next update after $(date -d @$REF_TS +%H:%M:%S)"

        for schedule in $SCHEDULE; do
                read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
                        $( echo " $schedule" | sed -e 's/[:,=,\,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
                START=$(( 60*$STARTHOUR + $STARTMINUTE ))
                END=$(( 60*$ENDHOUR + $ENDMINUTE ))

                if [ $REF_MIN -lt $START ]; then
                        NEXT_MIN=$START
                        break
                fi

                if [ $REF_MIN -ge $START ] && [ $REF_MIN -lt $END ]; then
                        TIME_IN_PERIOD=$(( REF_MIN - START ))
                        COMPLETE_INTERVALS=$(( TIME_IN_PERIOD / INTERVAL ))
                        CAND=$(( START + (COMPLETE_INTERVALS + 1) * INTERVAL ))
                        if [ $CAND -ge $END ]; then
                                NEXT_MIN=$END
                        else
                                NEXT_MIN=$CAND
                        fi
                        break
                fi
        done

        if [ $NEXT_MIN -eq -1 ]; then
                NEXT_MIN=$(( REF_MIN + ${DEFAULTINTERVAL:-240} ))
        fi

        echo $(( SCHEDULE_BASE + NEXT_MIN*60 ))
}

##############################################################################

# perform update with timeout protection (Kindle-compatible)
do_update_cycle () {
	logger "Starting update cycle"
	
	# Run the update in background
	sh ./update.sh &
	UPDATE_PID=$!
	
	# Wait for update to complete with timeout
	TIMEOUT=300  # 5 minutes
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

# use a 48 hour schedule
extend_schedule

# Main execution loop with error recovery
while true; do
        # Reload configuration and rebuild schedule in case it changed
        if [ -e "config.sh" ]; then
                source ./config.sh
        fi
        extend_schedule

        DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status)
        logger "Device status: $DEVICE_STATUS"
	
	case "$DEVICE_STATUS" in
		*"Screen Saver"*)
			logger "Device in screensaver mode - performing scheduled update"
			
			# Record start time for timeout detection
			UPDATE_START_TIME=$(currentTime)
			do_update_cycle
			UPDATE_END_TIME=$(currentTime)
			UPDATE_DURATION=$(( $UPDATE_END_TIME - $UPDATE_START_TIME ))
			
			logger "Update took $UPDATE_DURATION seconds"
			
                        # Wait for next scheduled update
                        NEXT_TS=$(get_next_update_epoch $(currentTime))
                        WAIT_SECONDS=$(( NEXT_TS - $(currentTime) ))
                        [ $WAIT_SECONDS -lt 300 ] && WAIT_SECONDS=300
                        logger "Next update scheduled at $(date -d @$NEXT_TS +%H:%M:%S)"
                        wait_for_suspend $WAIT_SECONDS
			;;
		*"Ready"*)
			logger "Device ready - performing scheduled update"
			
			# Record start time for timeout detection
			UPDATE_START_TIME=$(currentTime)
			do_update_cycle
			UPDATE_END_TIME=$(currentTime)
			UPDATE_DURATION=$(( $UPDATE_END_TIME - $UPDATE_START_TIME ))
			
			logger "Update took $UPDATE_DURATION seconds"
			
                        # Wait for next scheduled update
                        NEXT_TS=$(get_next_update_epoch $(currentTime))
                        WAIT_SECONDS=$(( NEXT_TS - $(currentTime) ))
                        [ $WAIT_SECONDS -lt 300 ] && WAIT_SECONDS=300
                        logger "Next update scheduled at $(date -d @$NEXT_TS +%H:%M:%S)"
                        wait_for_suspend $WAIT_SECONDS
			;;
		*)
			logger "Device in other state, waiting 60 seconds before recheck"
			wait_for_suspend 60
			;;
	esac
	
	# Safety check - if we somehow get here without sleeping, add a small delay
	sleep 1
done
