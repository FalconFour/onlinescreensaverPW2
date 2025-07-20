FOLDER=/mnt/us/extensions/onlinescreensaver/
# remove the screensaver folder
if [ -d "$FOLDER" ]; then
    echo "Removing screensaver folder $FOLDER"
    rm -rf "$FOLDER"
else
    echo "Screensaver folder $FOLDER does not exist, nothing to remove."
fi