# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kindle screensaver extension that automatically fetches screensaver images from a URL at scheduled intervals. It's optimized for Kindle Paperwhite 2 with power management and stability fixes, though it attempts to auto-detect features for other Kindle devices.

The project is a shell script-based system that integrates with Amazon's Kindle framework (KUAL) to provide:
- **Event-driven** scheduled screensaver updates using RTC wakeups
- Battery-efficient power management with coordinated suspend/wake cycles
- WiFi connection recovery and network diagnostics
- Configurable update intervals and time-based schedules

## Architecture

### Core Components

**`bin/scheduler.sh`** - Event-driven daemon using `lipc-wait-event`, managing:
- Power state event listening (`goingToScreenSaver`, `wakeupFromSuspend`, `readyToSuspend`)
- RTC alarm scheduling using device-specific real-time clocks  
- Scheduled execution of updates based on time-of-day configuration
- Automatic wakeup timer setting to prevent indefinite sleep

**`bin/update.sh`** - Single update execution script that:
- Manages WiFi connection state and recovery
- Downloads screensaver images with battery/charging status parameters
- Handles network timeouts and connection failures
- Updates the actual screensaver file and refreshes the display
- Runs with 5-minute timeout protection

**`bin/utils.sh`** - Shared utility functions providing:
- Power management coordination (begin_power_hold, end_power_hold)
- RTC wakeup alarm management with device auto-detection
- WiFi state monitoring and recovery mechanisms
- Battery-efficient suspend/wake logic with fallback modes

**`bin/config.sh`** - Configuration file containing:
- Update intervals and time-based schedules
- Image URL and screensaver file paths
- Power management settings
- Network and logging configuration

### Event-Driven Architecture (Latest)

The scheduler now operates purely on power state events instead of polling:

1. **`goingToScreenSaver`** - Device entering screensaver mode
   - Triggers immediate update cycle
   - No waiting or delays

2. **`wakeupFromSuspend`** - Device waking from RTC alarm
   - Waits 10 seconds for WiFi to stabilize
   - Performs scheduled update

3. **`readyToSuspend`** - Device about to sleep
   - Calculates seconds until next scheduled update
   - Sets RTC wakeup timer using `set_rtc_wakeup_relative`
   - Critical to prevent device sleeping indefinitely

### Key Technical Details

- **Power States**: Coordinates with powerd framework states (Ready, Screen Saver, Active)
- **WiFi Recovery**: Multi-stage recovery from "NA" connection states including service restarts
- **Timeout Protection**: All update operations run with 20-second timeout and proper process cleanup

## Common Development Tasks

### Testing the Extension
```bash
# Manual test run (connect via SSH first)
/mnt/us/extensions/onlinescreensaver/bin/scheduler.sh &

# Check schedule parsing
/mnt/us/extensions/onlinescreensaver/bin/checkschedule.sh

# Single update test
/mnt/us/extensions/onlinescreensaver/bin/update.sh
```

### Configuration Changes
Edit `bin/config.sh` for:
- `IMAGE_URI` - URL endpoint for screensaver images
- `SCHEDULE` - Time-based update intervals in "HH:MM-HH:MM=MINUTES" format

### Installation/Management via KUAL
The `menu.json` defines KUAL menu items:
- Update now (runs update.sh)
- Enable/disable auto-download (manages /etc/upstart/onlinescreensaver.conf)
- Uninstall

### Logging and Debugging
Logs are written to `/mnt/us/extensions/onlinescreensaver/log/onlinescreensaver.log` when `LOGGING=1` in config.sh. Key log patterns:
- RTC alarm setting/clearing operations
- WiFi state transitions and recovery attempts
- Power state coordination with powerd
- Network connectivity failures and retry logic
- Event-driven scheduler state changes

## Device Compatibility Notes

- **All Kindles**: Use event-driven lipc-wait-event based suspension
- **Screen resolution**: Must match device exactly (configurable via SCREENSAVERFILE path)

## Recent Changes

### Event-Driven Refactor
- Replaced polling loop with `lipc-wait-event` for power efficiency
- Added `get_seconds_until_next_update()` helper function
- Fixed `set_rtc_wakeup_relative()` to properly use relative time parameters
- Enhanced `do_update_cycle()` with 20-second timeout protection and background execution
- Simplified main execution flow to be purely reactive to power events

### Critical Functions
- `set_rtc_wakeup_relative(seconds)` - Sets RTC alarm for relative time from now
- `get_seconds_until_next_update()` - Calculates time until next scheduled update
- `do_update_cycle()` - Runs update.sh with 20-second timeout protection

## Important Instructions
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.