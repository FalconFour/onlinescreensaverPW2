#!/bin/sh
#
##############################################################################
#
# Checks the format of the schedule configuration value
#
##############################################################################

# change to directory of this script
cd "$(dirname "$0")"

# load configuration
if [ -e "config.sh" ]; then
	source ./config.sh
fi

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit
fi

# get minute of day
CURRENTMINUTE=$(( `date +%-H`*60 + `date +%-M` ))
CURRENT_TIME=$(date +%H:%M)

echo "Current time: $CURRENT_TIME ($CURRENTMINUTE minutes from midnight)"
echo "Default interval: $DEFAULTINTERVAL minutes"
echo ""

# SCHEDULE="21:00-24:00=30"
ACTIVE_SCHEDULE=""
for schedule in $SCHEDULE; do
	echo "-------------------------------------------------------"
	echo "Parsing \"$schedule\""
	read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
		$( echo " $schedule" | sed -e 's/[:,=,\,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
	echo "	Starts at $STARTHOUR hours and $STARTMINUTE minutes"
	echo "	Ends at $ENDHOUR hours and $ENDMINUTE minutes"
	echo "	Interval is $INTERVAL minutes"

	START=$(( 60*$STARTHOUR + $STARTMINUTE ))
	END=$(( 60*$ENDHOUR + $ENDMINUTE ))

	if [ $END -lt $START ]; then
		echo "!!!!!!! End time is before start time."
	fi

	if [ $CURRENTMINUTE -ge $START ] && [ $CURRENTMINUTE -lt $END ]; then
		echo "    --> This is the active setting"
		ACTIVE_SCHEDULE="$schedule"
		ACTIVE_INTERVAL=$INTERVAL
		
		# Calculate next update time based on interval boundaries
		TIME_IN_PERIOD=$(( $CURRENTMINUTE - $START ))
		COMPLETE_INTERVALS=$(( $TIME_IN_PERIOD / $INTERVAL ))
		NEXT_INTERVAL_START=$(( $START + ($COMPLETE_INTERVALS + 1) * $INTERVAL ))
		
		if [ $NEXT_INTERVAL_START -ge $END ]; then
			echo "    --> Next interval would exceed this schedule period"
			echo "    --> Will switch to next schedule period or use default interval"
		else
			MINUTES_TO_WAIT=$(( $NEXT_INTERVAL_START - $CURRENTMINUTE ))
			NEXT_HOUR=$(( $NEXT_INTERVAL_START / 60 ))
			NEXT_MIN=$(( $NEXT_INTERVAL_START % 60 ))
			echo "    --> Next update in $MINUTES_TO_WAIT minutes (at $(printf "%02d:%02d" $NEXT_HOUR $NEXT_MIN))"
		fi
	fi
done

if [ -z "$ACTIVE_SCHEDULE" ]; then
	echo ""
	echo "No active schedule found - would use default interval of $DEFAULTINTERVAL minutes"
fi
