# Online Screensaver for Kindle

An event-driven screensaver extension that automatically fetches images from a URL at scheduled intervals. Originally developed by [peterson on MobileRead forums](https://www.mobileread.com/forums/showthread.php?t=236104) and enhanced with significant power management improvements, this version transforms your Kindle into an ultra-low-power, always-on display perfect for Home Assistant dashboards, weather displays, or any application that can serve Kindle-compatible full-screen images.

## Key Features

**Event-Driven Architecture**
- Uses `lipc-wait-event` to respond to power state changes instead of polling
- Only activates during screensaver transitions, suspend/wake cycles, and scheduled updates
- Eliminates complex timing loops in favor of reactive event handling

**Power Efficiency**
- Designed for maximum battery life - a Kindle Basic (2014/7th Generation) can run nearly a week on a single charge
- WiFi automatically disabled after each update cycle to prevent WiFi bring-up issues on wake
- Coordinated with Kindle's power management framework for optimal suspend/wake/RTC scheduling behavior

**Reliable Operation**
- 20-second timeout protection prevents hung updates
- Multi-stage WiFi recovery handles connection issues gracefully  
- Automatic RTC wakeup scheduling prevents indefinite sleep
- Works across Kindle generations with unified event-driven approach

## How It Works

The scheduler operates purely on power state events:

1. **`goingToScreenSaver`** - Device entering screensaver mode → performs immediate update
2. **`wakeupFromSuspend`** - Device waking from RTC alarm → enables WiFi, waits 10s for WiFi, then updates
3. **`readyToSuspend`** - Device about to sleep → calculates and sets RTC timer for next scheduled update

This approach ensures updates happen at the right moments while allowing the device to sleep efficiently between updates.

## Use Cases

- **Home Assistant dashboards** - Display sensor data, weather, calendar, or device status
- **Weather displays** - Automated weather reports and forecasts
- **Daily comics** - Fresh comic strip each morning  
- **Inspirational content** - Quotes, artwork, or rotating imagery
- **Status displays** - Any application that can generate Kindle-compatible images

The key requirement is a server that can provide PNG images in your Kindle's exact screen resolution with optional battery level and charging status parameters.

## Prerequisites

- **KUAL v2 or later** installed
- **linkss installed** ("screensavers hack") 
- **SSH access** (optional) for configuration and testing (USBNet recommended)

## Installation

1. Download and unzip into the extensions folder:
   - Via SSH: `/mnt/us/extensions/`
   - Via USB: `extensions/` folder at root of Kindle volume
   - You should have `extensions/onlinescreensaver/bin/update.sh` and related files present.

2. Edit `onlinescreensaver/bin/config.sh` with your settings:
   - `IMAGE_URI` - Your image server URL
   - `SCHEDULE` - Update times in "HH:MM-HH:MM=MINUTES" format
   - `SCREENSAVERFILE` - Path to your screensaver image (the default normally works with linkss)

   **Important:** Use an editor that supports Unix line endings (e.g., notepad++ on Windows)

## Configuration

The main settings in `config.sh`:

```bash
# Update schedule - different intervals for different times of day
SCHEDULE="00:00-07:00=30 07:00-23:00=8 23:00-24:00=30"

# Your image server URL (will receive batteryLevel and isCharging parameters)
IMAGE_URI="http://192.168.1.100:5000"

# Where to save the downloaded image
SCREENSAVERFILE=/mnt/us/linkss/screensavers/bg_ss00.png
```

**Note:** The extension copies images to `/mnt/us/linkss/screensavers/` by default. Back up any existing screensaver images you want to preserve. For predictable results, use only one screensaver image file.

## Usage

**Via KUAL Menu:**
- Update screensaver immediately (one-time)
- Enable/disable automatic updates  
- Uninstall the extension

**Manual Testing (recommended before enabling auto-updates):**
```bash
# Connect via SSH and test manually
/mnt/us/extensions/onlinescreensaver/bin/scheduler.sh &
```

Exit SSH and observe behavior. If issues occur, rebooting the Kindle will restore normal operation.

**Image Requirements:**
- PNG format in your device's exact screen resolution
- "Clean" PNG files work best (test with `eips -f -g image.png` if unsure)
- Server may optionally handle `batteryLevel` and `isCharging` query parameters

## Home Assistant Integration

For Home Assistant users, the recommended approach is [sibbl's Lovelace Kindle Screensaver](https://github.com/sibbl/hass-lovelace-kindle-screensaver) add-on, which generates properly formatted Kindle images and handles battery status reporting.

**WebHook Configuration (Common Setup Issue):**

When configuring the battery status webhook (per the [How to set up the webhook](https://github.com/sibbl/hass-lovelace-kindle-screensaver?tab=readme-ov-file#how-to-set-up-the-webhook) guide), the naming can be confusing:

1. **In Home Assistant:** Create an automation blueprint with a "Webhook ID" (e.g., `set_kindle_battery_level`)
2. **In the Screensaver Add-on:** Set `HA_BATTERY_WEBHOOK` parameter to the same name (e.g., `set_kindle_battery_level`)

The `HA_BATTERY_WEBHOOK` config parameter should match exactly what you entered as the "Webhook ID" in your Home Assistant automation blueprint. For multiple Kindles, use `HA_BATTERY_WEBHOOK_2`, `HA_BATTERY_WEBHOOK_3`, etc. This will allow you to display the Kindle's battery status on-screen, looping back through HA and into the presented image on the display.

Your `IMAGE_URI` would typically point to the add-on: `http://your-ha-ip:5000`

## Device Compatibility

Tested and optimized for all Kindle generations with firmware 5 or newer. The event-driven architecture provides consistent behavior across:
- Kindle Paperwhite (all generations)
- Kindle Basic/Touch models  
- Kindle Oasis models

Behavior with 3G models is device-dependent but generally works well.

## Power Management Details

The extension coordinates carefully with Kindle's power management:
- **WiFi Usage**: Enabled only during update cycles, then disabled to preserve battery
- **Update Timing**: Scheduled updates use RTC alarms to wake the device at precise intervals
- **Timeout Protection**: Updates complete within 20 seconds or are terminated to prevent battery drain
- **Sleep Coordination**: Properly signals readiness to suspend, allowing normal power management

## Troubleshooting

**No updates occurring:** This is the most common issue during setup and debugging:
- Verify `IMAGE_URI` is accessible and returns valid PNG images
- **After making config changes:** Always reboot the Kindle (hold power ~5 seconds → "Reboot"). The Kindle's USB filesystem can become wedged with old/corrupted script versions in memory, especially after mounting USB and editing files. Rebooting ensures changes take effect properly.
- Check logs after expected update periods (e.g., after 1 hour with 8-minute intervals) - connectivity issues are often hidden in logs with no visible errors

**Monitoring via logs:** Enable `LOGGING=1` in config.sh and watch `/mnt/us/extensions/onlinescreensaver/log/onlinescreensaver.log`:
```bash
# SSH into Kindle and monitor live
tail -f /mnt/us/extensions/onlinescreensaver/log/onlinescreensaver.log
```
Look for WiFi state changes, RTC timer settings, and any connection failures during expected update windows.

**White screen after update:** Image may not be "clean" PNG or wrong resolution

**High battery drain:** Verify WiFi is being disabled after updates (check logs for "Ensuring WiFi is turned off")

**Device not waking:** Ensure RTC wakeup alarms are being set (visible in logs when `LOGGING=1`)

**Logs:** Enable logging in config.sh and check `extensions/onlinescreensaver/log/onlinescreensaver.log`

## Uninstalling

1. Use KUAL menu to disable auto-updates first
2. Delete the `onlinescreensaver` folder from extensions directory
3. Reboot if you experience any residual behavior

## Disclaimer

This extension has been tested primarily on Kindle Paperwhite 2 and other modern Kindle devices. While designed to be safe and reliable, you use this extension at your own risk. The event-driven architecture minimizes system impact, but as with any extension that manages power states, thorough testing is recommended.

If issues occur, rebooting the Kindle will restore normal operation.