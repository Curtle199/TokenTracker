# TokenTracker

Real-time market analytics dashboard built with Python and Lua, featuring automated data ingestion, trend analysis, alerting, and decision-support signals.

## Overview

TokenTracker is a World of Warcraft addon paired with a Python data fetcher. The system pulls external token pricing data, processes it, and displays actionable insights through an in-game dashboard and mini tracker.

The project was built to solve a simple problem: checking token prices manually is inefficient, inconsistent, and annoying. TokenTracker automates that workflow and turns raw price updates into clear buy, wait, or avoid signals.

## Features

- Real-time token price monitoring
- Automated external data ingestion
- Smart buy window calculation
- Trend detection
- Undervalued score from 0 to 100
- In-game alerts with anti-spam logic
- Mini tracker HUD
- Background automation with Windows Task Scheduler
- Lightweight UI designed for fast decision-making

## How It Works

The project is split into two parts:

### 1. Python Fetcher
A Python script pulls pricing data from an external source and writes the results into a Lua-readable file.

### 2. WoW Addon
The addon reads the generated data file and displays:
- current price
- trend direction
- buy window
- undervalued score
- recent history
- alert state

This creates a simple pipeline:

`External Data Source -> Python Fetcher -> Lua Data File -> WoW Addon UI`
## Why This Project Matters

This project demonstrates the ability to design and implement a complete data-driven system, including:

- automated data ingestion
- cross-language integration (Python → Lua)
- background task scheduling
- real-time UI updates
- decision-support logic

Although built within a game environment, the architecture mirrors real-world monitoring dashboards and analytics tools.
## Tech Stack

- Python (data ingestion)
- Lua (UI and logic layer)
- Windows Task Scheduler (automation)
- External data source (token pricing)
