TokenTracker Addon

A World of Warcraft addon that tracks WoW Token prices using external data, provides market insights, and helps identify optimal buy opportunities.

====================
Features
Real-time WoW Token price tracking
Trend detection (rising, falling, flat)
Smart buy window calculation
Undervalued scoring system (0–100)
Price alerts with optional sound
Mini tracker HUD
Automated data updates via Python + Task Scheduler
====================
Installation
Addon Files

Navigate to your WoW AddOns directory:

C:\Program Files (x86)\World of Warcraft_retail_\Interface\AddOns\

Create a folder named:

TokenTracker

Place the following files inside:

TokenTracker.lua
TokenTracker.toc
TokenTrackerExternal.lua
token_fetcher.py

Install Python

Download and install Python:

https://www.python.org/downloads/

During installation, ensure:
Add Python to PATH

Install Dependencies

Open Command Prompt or PowerShell and run:

pip install requests

Test the Data Fetcher

Navigate to the addon directory:

cd "C:\Program Files (x86)\World of Warcraft_retail_\Interface\AddOns\TokenTracker"

Run:

python token_fetcher.py

This should update TokenTrackerExternal.lua with current token data.

====================
In-Game Usage

Enable the addon from the WoW AddOns menu.

Commands:

/tt
Opens the main tracker window

/ttmini
Toggles the mini tracker HUD

====================
Automatic Updates (Recommended)

To keep data current, configure Windows Task Scheduler.

Open Task Scheduler
Click "Create Task"
General Tab

Name: TokenTracker Update

Triggers Tab

New Trigger:

Begin the task: Daily
Repeat every: 5 minutes
Duration: 1 day
Actions Tab

Program/script:
C:\Users\YOUR_USERNAME\AppData\Local\Programs\Python\Python3xx\python.exe

Add arguments:
token_fetcher.py

Start in:
C:\Program Files (x86)\World of Warcraft_retail_\Interface\AddOns\TokenTracker

Settings Tab

Enable:

Allow task to be run on demand
Run task as soon as possible after a scheduled start is missed
====================
Features Overview

Smart Buy Window

Adjusts dynamically based on:
24-hour average price
24-hour low
Current trend direction

Undervalued Score

Composite score (0–100) based on:
Price relative to average
Proximity to recent low
Market trend

Alerts

Chat notification when entering buy window
Optional sound alert
Anti-spam logic prevents repeated alerts

Mini Tracker

Compact UI showing:
Current price
Trend direction
Buy/Wait/Avoid signal
====================
Troubleshooting

Addon Not Showing:

Folder name must be exactly "TokenTracker"
.toc filename must match folder name

Data Not Updating:

Verify Task Scheduler is running
Confirm Python path is correct
Run token_fetcher.py manually to check for errors

UI Not Updating:
Use:
/reload

====================
Notes
Data is sourced externally and written into TokenTrackerExternal.lua
The addon reads this file locally (no direct web requests from WoW)
Designed for low overhead and stability
====================
License

Personal use and modification permitted.