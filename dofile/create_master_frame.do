capture log close

**# Purpose 
*Script to create master frame for Jakarta's AQM data

**# Directory
* Set base directory and folder paths
global base_dir "/Users/aryaswarnata/Library/CloudStorage/OneDrive-Personal/WBG/Air Pollution/data/aqi_dlh_jak/"
global raw_dir "${base_dir}raw/"
global mtr_dir "${base_dir}master/"
global out_dir "${base_dir}output/"
global log_dir "${base_dir}log/"

clear
set more off

**# Define start and end times 

// 
local start = clock("2025-04-10 00:00:00", "YMDhms")
local end   = clock("2026-04-10 00:00:00", "YMDhms")
local interval = 30 * 60 * 1000  // 30 minutes in milliseconds
local n_obs = floor((`end' - `start') / `interval') + 1

**# Create datetime template 

set obs `n_obs'
gen double datetime = `start' + (_n - 1) * `interval'
format datetime %tc
gen str25 timestamp = string(datetime, "%tcCCYY-NN-DD_HH:MM:SS") + "Z"

tempfile datetime
	save `datetime'
	
**# Cross with station ID 
use "${mtr_dir}jakarta_aqm-station_list.dta", clear
keep id

cross using `datetime'

sort id datetime

**# Save file
save "${mtr_dir}master_frame.dta", replace
