* Start log file
cap log close
log using "${log_dir}merge_to_master.log", replace

** Purpose 
* Append data with master and prepare it for inverse weighting (assignment to Kelurahan)

**# Directory #
global base_dir "/Users/aryaswarnata/Library/CloudStorage/OneDrive-Personal/WBG/Air Pollution/data/aqi_dlh_jak/"
global raw_dir "${base_dir}raw/"
global mtr_dir "${base_dir}master/" 
global pro_dir "${base_dir}processed/"
global log_dir "${base_dir}log/"

**# Get the latest PM2.5 data #
* Find the latest file matching the pattern
local file_pattern "append_udara.jakarta_as-of_"
local latest_date = ""
local latest_file = ""

* Get all matching files and find the most recent one
local files : dir "${pro_dir}" files "`file_pattern'*"
foreach file of local files {
    * Extract date from filename (assumes YYYY-MM-DD format after as-of_)
    local file_date = substr("`file'", strlen("`file_pattern'")+1, 10)
    
    * Compare dates (string comparison works for YYYY-MM-DD format)
    if "`file_date'" > "`latest_date'" {
        local latest_date = "`file_date'"
        local latest_file = "`file'"
    }
}

* Display which file will be used
di "Using latest file: `latest_file' (date: `latest_date')"

* Use the latest file
use "${pro_dir}`latest_file'", clear


**# Define beginning cutoff date #**
* This should be manually set to your desired beginning date
local beginning_date = "2025-04-10" // Change this to your desired start date
local beginning_datetime = clock("`beginning_date' 00:00:00", "YMD hms")
di "Beginning cutoff datetime: `beginning_datetime' (`beginning_date' 00:00:00)"

**# Calculate previous day for end cutoff #**
* Calculate the previous day of the latest date for the end cutoff
local latest_date_dt = date("`latest_date'", "YMD")
local prev_day_dt = `latest_date_dt' - 1
local prev_day = string(`prev_day_dt', "%tdCCYY-NN-DD")
local end_cutoff_datetime = clock("`prev_day' 11:30:00", "YMD hms")
di "End cutoff datetime: `end_cutoff_datetime' (`prev_day' 11:30:00)"

**# Open master data #
preserve
    use "${mtr_dir}master_frame", clear
    
    * Apply both beginning and end cutoffs
    drop if datetime < `beginning_datetime' | datetime > `end_cutoff_datetime'
    
    tempfile master
    save `master'
restore

**# Append with the master data #
merge 1:1 id datetime using `master'
drop if _merge==1
drop _merge
sort id datetime
merge m:1 id using "${mtr_dir}jakarta_aqm-station_list", keepusing(latitude longitude)
ren 	id sensor_id
keep 	sensor_id  longitude  latitude  datetime pm25
order 	sensor_id  longitude  latitude  datetime pm25

**# Save with date range in filename #**
save "${pro_dir}pm25_jakarta_`beginning_date'_to_`prev_day'", replace
