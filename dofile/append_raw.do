* Start log file
cap log close
log using "${log_dir}import_append_csv.log", replace


**# Purpose 
*Script to import and append all CSV files (Jakarta AQM) from raw folder

**# Directory
global base_dir "/Users/aryaswarnata/Library/CloudStorage/OneDrive-Personal/WBG/Air Pollution/data/aqi_dlh_jak/"
global raw_dir "${base_dir}raw/"
global mtr_dir "${base_dir}master/" 
global pro_dir "${base_dir}processed/"
global log_dir "${base_dir}log/"

* Set more off for continuous output
set more off

* Format for datetime display
set sortseed 123456

**# Import the csv

* Create a temporary file to store list of CSV files
tempfile file_list
file open flist using `file_list', write replace

* Get all CSV files in the raw directory
local files: dir "${raw_dir}" files "*.csv"
foreach file of local files {
    file write flist "`file'" _n
}
file close flist

* Read the list of files
file open flist using `file_list', read
file read flist line

* Counter for files
local count = 0

* Create empty master dataset for appending
clear
tempfile master
save `master', emptyok

* Loop through each file and append
while r(eof)==0 {
    local ++count
    
    display as text "Importing file `count': `line'"
    
    * Import the CSV file
    import delimited "${raw_dir}`line'", clear varnames(1)
    
    * Rename variables to standard names
    cap rename tanggal timestamp
    cap rename value pm25
    replace pm25=. if pm25==0
    
    * Add a variable to identify the source file
    gen file_source = "`line'"
    
    * Convert string timestamp to Stata datetime format
    * Format example: "2025-04-12 14:00:00Z"
    
    * First try with a more precise format mask
    gen datetime = clock(timestamp, "YMD HMS")
    format datetime %tc
    
    * If that didn't work, try alternative approach
    count if missing(datetime)
    if r(N) > 0 {
        drop datetime
        * Try parsing the components manually
        gen year = substr(timestamp, 1, 4)
        gen month = substr(timestamp, 6, 2)
        gen day = substr(timestamp, 9, 2)
        gen hour = substr(timestamp, 12, 2)
        gen minute = substr(timestamp, 15, 2)
        gen second = substr(timestamp, 18, 2)
        
        * Convert to numeric
        destring year month day hour minute second, replace
        
        * Create datetime using mdy() and hms()
        gen double datetime = mdyhms(month, day, year, hour, minute, second)
        format datetime %tc
        
        * Clean up temporary variables
        drop year month day hour minute second
    }
    
    * Round minutes to nearest 00 or 30
    * First extract components from datetime
    gen int hour_part = hh(datetime)
    gen int minute_part = mm(datetime)
    
    * Calculate rounded minutes
    gen int rounded_minute = 0
    replace rounded_minute = 30 if minute_part >= 15 & minute_part < 45
    replace rounded_minute = 0 if minute_part >= 45
    replace hour_part = hour_part + 1 if minute_part >= 45
    
    * Recreate datetime with rounded minutes
    gen date_part = dofc(datetime)
    gen double datetime_rounded = dhms(date_part, hour_part, rounded_minute, 0)
    format datetime_rounded %tc
    
    * Replace original datetime with rounded version
    drop datetime
    rename datetime_rounded datetime
    
    * Clean up temporary variables
    drop hour_part minute_part rounded_minute date_part
    
    * Label variables
    label var datetime  	"Date and time (rounded to nearest 00/30 min)"
    label var pm25 			"PM2.5 value"
    label var file_source 	"Source filename"
    label var timestamp 	"Original timestamp string"
    
    * Append to master
    append using `master'
    save `master', replace
    
    * Read next file
    file read flist line
}
file close flist

**# Duplicates

* Sort the data by id and datetime
gsort id datetime -pm25  // Sort by id, datetime, and descending pm25 (so non-missing values come first)

* Remove duplicates, keeping the first record for each id-datetime combination
* Since we sorted with non-missing pm25 first, this keeps those values
duplicates drop id datetime, force

* Save the final appended dataset with a filename based on the latest date
* First get the latest date by looking at the file names
local latest_date = ""
local latest_timestamp = 0

**# Get the latest file name

foreach file of local files {
    * Try to extract date from filename pattern "udara.jakarta_YYYY-MM-DD.csv"
    if regexm("`file'", "([0-9]{4}-[0-9]{2}-[0-9]{2})") {
        local file_date = regexs(1)
        
        * Convert to Stata date for comparison
        local file_timestamp = date("`file_date'", "YMD")
        
        * Update if this is the latest
        if `file_timestamp' > `latest_timestamp' {
            local latest_timestamp = `file_timestamp'
            local latest_date = "`file_date'"
        }
    }
}

* Create the output filename
local output_filename = "append_udara.jakarta_as-of_`latest_date'"

* Replace error reading
replace pm25=. if pm25>500


**# Saving the file
* Save the file with the date-based filename (only .dta)
save "${pro_dir}`output_filename'.dta", replace

* Display the filename used
display as text "File saved as: ${pro_dir}`output_filename'.dta"

* Summary statistics of the appended data
describe
summarize

* Close log
log close

display as text "Done! Appended `count' CSV files."
