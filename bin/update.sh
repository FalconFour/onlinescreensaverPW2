#!/bin/sh
#
##############################################################################
#
# Fetch screensaver from a configurable URL.
cd "$(dirname "$0")"
# load configuration
if [ -e "config.sh" ]; then
    source ./config.sh
else
    TMPFILE=/tmp/tmp.onlinescreensaver.png
fi
# load utils
if [ -e "utils.sh" ]; then
    source ./utils.sh
else
    echo "Could not find utils.sh in `pwd`"
    exit
fi
# do nothing if no URL is set
if [ -z $IMAGE_URI ]; then
    logger "No image URL has been set. Please edit config.sh."
    return
fi

# Check initial WiFi status and log it
WIFI_STATUS=`lipc-get-prop com.lab126.cmd wirelessEnable`
logger "Initial WiFi status: $WIFI_STATUS"

# Whether to disable WiFi after this run.  Respect the value from config.sh
# and ignore the previous WiFi state so that WiFi can stay enabled across
# multiple update cycles when desired.
DISABLE_WIFI_AFTER=${DISABLE_WIFI:-0}

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
logger "WiFi connection state: $WIFI_CONNECTION"

# If the connection state looks invalid (e.g. NA) attempt a WiFi restart
case "$WIFI_CONNECTION" in
    "NA"|"DISABLED")
        logger "WiFi connection state appears invalid ($WIFI_CONNECTION). Restarting WiFi"
        lipc-set-prop com.lab126.cmd wirelessEnable 0
        sleep 2
        lipc-set-prop com.lab126.cmd wirelessEnable 1
        logger "Waiting 10 seconds for WiFi to reinitialize..."
        sleep 10
        WIFI_CONNECTION=`lipc-get-prop com.lab126.wifid cmState`
        logger "WiFi state after restart: $WIFI_CONNECTION"
        ;;
esac

RETRY_COUNT=0
CONNECTED=0
while [ $RETRY_COUNT -lt 2 ] && [ 0 -eq $CONNECTED ]; do
    TIMER=${NETWORK_TIMEOUT}
    PING_ATTEMPTS=0

    logger "Starting network connectivity test with ${NETWORK_TIMEOUT} second timeout (attempt $((RETRY_COUNT+1)))"

    while [ 0 -eq $CONNECTED ]; do
        PING_ATTEMPTS=$((PING_ATTEMPTS + 1))
    
    # test whether we can ping outside - with more verbose logging
    if /bin/ping -c 1 -w 2 $TEST_DOMAIN > /dev/null 2>&1; then
        CONNECTED=1
        logger "Successfully connected to internet after $PING_ATTEMPTS ping attempts (${NETWORK_TIMEOUT} - $TIMER seconds elapsed)"
    else
        # Log ping failure details every 10 attempts to avoid log spam
        if [ $((PING_ATTEMPTS % 10)) -eq 0 ]; then
            PING_RESULT=$(/bin/ping -c 1 -w 2 $TEST_DOMAIN 2>&1)
            logger "Ping attempt $PING_ATTEMPTS to $TEST_DOMAIN failed. Last error: $PING_RESULT"
            echo "$(date): Ping attempt $PING_ATTEMPTS failed: $PING_RESULT" >> $LOGFILE

            # Check WiFi status during failed attempts
            CURRENT_WIFI_STATE=`lipc-get-prop com.lab126.wifid cmState`
            logger "Current WiFi state during ping failure: $CURRENT_WIFI_STATE"

            # Also log current powerd state to correlate with WiFi issues
            CURRENT_POWER_STATE=`lipc-get-prop com.lab126.powerd status`
            logger "Current powerd status during ping failure: $CURRENT_POWER_STATE"
            sleep 1
        fi
        
        # if we can't connect, check timeout or sleep for 1s
        TIMER=$((TIMER - 1))
        if [ 0 -eq $TIMER ]; then
            logger "No internet connection after ${NETWORK_TIMEOUT} seconds and $PING_ATTEMPTS ping attempts, aborting."
            echo "$(date): Network timeout after ${NETWORK_TIMEOUT} seconds, $PING_ATTEMPTS ping attempts to $TEST_DOMAIN" >> $LOGFILE

            # Log final network diagnostics
            FINAL_WIFI_STATUS=`lipc-get-prop com.lab126.cmd wirelessEnable`
            FINAL_WIFI_STATE=`lipc-get-prop com.lab126.wifid cmState`
            echo "$(date): Final WiFi status: enabled=$FINAL_WIFI_STATUS, state=$FINAL_WIFI_STATE" >> $LOGFILE

            POWER_STATE_SNAPSHOT=`lipc-get-prop com.lab126.powerd status`
            echo "$(date): Powerd state during network timeout: $POWER_STATE_SNAPSHOT" >> $LOGFILE
            logger "Powerd state during network timeout: $POWER_STATE_SNAPSHOT"

            if [ $RETRY_COUNT -lt 1 ]; then
                logger "Retrying network connection after restarting WiFi"
                lipc-set-prop com.lab126.cmd wirelessEnable 0
                sleep 2
                lipc-set-prop com.lab126.cmd wirelessEnable 1
                logger "Waiting 10 seconds for WiFi to reinitialize..."
                sleep 10
                RETRY_COUNT=$((RETRY_COUNT + 1))
            else
                break
            fi
        else
            sleep 1
        fi

    fi
done

if [ 1 -eq $CONNECTED ]; then
    logger "Network connection established, proceeding with image download"
    
    POWERD_OUTPUT=`/usr/bin/powerd_test -s`
    batteryLevel=`echo "$POWERD_OUTPUT" | awk -F: '/Battery Level/ {print substr($2, 1, length($2)-1) + 0}'`
    isCharging=`echo "$POWERD_OUTPUT" | awk -F: '/Charging/ {print substr($2,2,length($2))}'`
    IMAGE_URI_WITH_PARAMS="$IMAGE_URI?batteryLevel=$batteryLevel&isCharging=$isCharging"

    # Capture wget output and exit code for detailed logging
    WGET_OUTPUT=$(wget --no-check-certificate -q $IMAGE_URI_WITH_PARAMS -O $TMPFILE 2>&1)
    WGET_EXIT_CODE=$?
    
    if [ $WGET_EXIT_CODE -eq 0 ]; then
        mv $TMPFILE $SCREENSAVERFILE
        logger "Screen saver image updated successfully from $IMAGE_URI"
        # refresh screen
        if [ `lipc-get-prop com.lab126.powerd status | grep "Ready" | wc -l` -gt 0 ] || [ `lipc-get-prop com.lab126.powerd status | grep "Screen Saver" | wc -l` -gt 0 ]
        then
            logger "Updating image on screen"
            eips -f -g $SCREENSAVERFILE
        fi
    else
        # Log detailed wget failure information
        logger "wget failed with exit code $WGET_EXIT_CODE when downloading $IMAGE_URI"
        echo "$(date): wget failed with exit code $WGET_EXIT_CODE when downloading $IMAGE_URI" >> $LOGFILE
        
        # Log wget error output if available
        if [ -n "$WGET_OUTPUT" ]; then
            echo "$(date): wget error output: $WGET_OUTPUT" >> $LOGFILE
            logger "wget error: $WGET_OUTPUT"
        fi
        
        # Log common wget exit code meanings
        case $WGET_EXIT_CODE in
            1) echo "$(date): wget error: Generic error code" >> $LOGFILE ;;
            2) echo "$(date): wget error: Parse error (command line options)" >> $LOGFILE ;;
            3) echo "$(date): wget error: File I/O error" >> $LOGFILE ;;
            4) echo "$(date): wget error: Network failure" >> $LOGFILE ;;
            5) echo "$(date): wget error: SSL verification failure" >> $LOGFILE ;;
            6) echo "$(date): wget error: Username/password authentication failure" >> $LOGFILE ;;
            7) echo "$(date): wget error: Protocol errors" >> $LOGFILE ;;
            8) echo "$(date): wget error: Server issued an error response" >> $LOGFILE ;;
            *) echo "$(date): wget error: Unknown exit code $WGET_EXIT_CODE" >> $LOGFILE ;;
        esac
        
        # Clean up temp file if it exists but is incomplete
        if [ -f $TMPFILE ]; then
            rm -f $TMPFILE
            logger "Removed incomplete temporary file $TMPFILE"
        fi
        
        if [ 1 -eq $DONOTRETRY ]; then
            touch $SCREENSAVERFILE
            logger "Created empty screensaver file due to DONOTRETRY flag"
        fi
    fi
else
    logger "Failed to establish network connection, skipping image download"

    echo "$(date): Script aborted due to network connectivity failure" >> $LOGFILE
fi
done

# disable wireless if configured to do so
if [ 1 -eq "$DISABLE_WIFI_AFTER" ]; then
    logger "Disabling WiFi"
    lipc-set-prop com.lab126.cmd wirelessEnable 0
fi