#############################################################################
### ONLINE-SCREENSAVER CONFIGURATION SETTINGS
#############################################################################

# Interval in MINUTES in which to update the screensaver by default. This
# setting will only be used if no schedule (see below) fits. Note that if the
# update fails, the script is not updating again until INTERVAL minutes have
# passed again. So chose a good compromise between updating often (to make
# sure you always have the latest image) and rarely (to not waste battery).
DEFAULTINTERVAL=30

# Schedule for updating the screensaver. Use checkschedule.sh to check whether
# the format is correctly understood. 
#
# The format is a space separated list of settings for different times of day:
#       SCHEDULE="setting1 setting2 setting3 etc"
# where each setting is of the format
#       STARTHOUR:STARTMINUTE-ENDHOUR:ENDMINUTE=INTERVAL
# where
#       STARTHOUR:STARTMINUTE is the time this setting starts taking effect
#       ENDHOUR:ENDMINUTE is the time this setting stops being active
#       INTERVAL is the interval in MINUTES in which to update the screensaver
#
# Time values must be in 24 hour format and not wrap over midnight.
# EXAMPLE: "00:00-06:00=480 06:00-18:00=15 18:00-24:00=30"
#          -> Between midnight and 6am, update every 4 hours
#          -> Between 6am and 6pm (18 o'clock), update every 15 minutes
#          -> Between 6pm and midnight, update every 30 minutes
#
# Use the checkschedule.sh script to verify that the setting is correct and
# which would be the active interval.
SCHEDULE="00:00-07:00=30 07:00-23:00=8 23:00-24:00=30"

# URL of screensaver image. This really must be in the EXACT resolution of
# your Kindle's screen (e.g. 600x800 or 758x1024) and really must be PNG.
IMAGE_URI="http://10.0.1.31:5000"

# folder that holds the screensavers
SCREENSAVERFOLDER=/mnt/us/linkss/screensavers

# In which file to store the downloaded image. Make sure this is a valid
# screensaver file. E.g. check the current screensaver folder to see what
# the first filename is, then just use this. THIS FILE WILL BE OVERWRITTEN!
SCREENSAVERFILE=$SCREENSAVERFOLDER/bg_ss00.png

# Whether to create log output (1) or not (0).
LOGGING=1

# Where to log to - either /dev/stderr for console output, or an absolute
# file path (beware that this may grow large over time!)
#LOGFILE=/dev/stderr
LOGFILE=/mnt/us/extensions/onlinescreensaver/log/onlinescreensaver.log

# the temporary file to download the screensaver image to
TMPFILE=/tmp/tmp.onlinescreensaver.png
