# Jakarta PM2.5 Air Quality Analysis Project

## Project Overview

This project consists of two integrated components that work together to collect, process, and analyze PM2.5 air quality data across Jakarta at the kelurahan (sub-district) level:

1. **Data Collection**: An automated scraper that collects high-frequency PM2.5 data from Jakarta's official air quality monitoring network
2. **Spatial Analysis**: An interpolation system that transforms point-based sensor measurements into comprehensive pollution estimates for all 267 kelurahan in Jakarta

Together, these components create a complete workflow from raw data acquisition to detailed spatial analysis, enabling a comprehensive understanding of air pollution patterns across Jakarta.

## Why This Project Matters

High-quality, high-frequency, and extensive sensor networks are key for good air quality data. Jakarta's Environmental Agency provides excellent data with 30-minute and 1-hour interval readings of PM2.5 across 110 sensors throughout the city. This data is publicly accessible through their website.

However, there are two significant limitations that this project addresses:

1. **Data Persistence**: Historical data is only available for the past 2 days on the official website, with no published procedure to access older data. This necessitates automatic scraping to build a complete historical dataset.

2. **Spatial Coverage**: Air quality sensors only exist at specific locations, leaving many areas without direct measurements. Spatial interpolation is needed to estimate pollution levels for all kelurahan across Jakarta.

## Complete Workflow

```
[Jakarta's Air Quality Website] → [Automated Scraper] → [Google Sheets] → [Email as CSV] → [R Analysis] → [Kelurahan-level PM2.5 Estimates]
```

## Part 1: Data Collection System

### What the Scraper Does

The scraper performs three main functions:

1. **Collects Air Quality Data**: Automatically fetches PM2.5 readings from 110+ monitoring stations across Jakarta every 2 days
2. **Stores Data**: Saves all collected data in a Google Sheet named "Data Udara"
3. **Sends Reports**: Emails the data as a CSV file to a specified email address

### How the Scraper Works

The main function (`getUdaraJakarta()`) checks if 2 days have passed since the last run. If so, it:
1. Collects new air quality data
2. Waits briefly for processing
3. Emails the data as a CSV file
4. Updates the "last run" timestamp

The data collection function (`getUdaraJakartaData()`) connects to Jakarta's air quality API and fetches PM2.5 data from over 100 monitoring stations throughout the city. It then organizes this data into a Google Sheet with columns for station ID, date, and PM2.5 value.

The email function (`kirimSheetSebagaiCSV()`) converts the Google Sheet data to CSV format and emails it to a designated recipient with the current date in the subject line and filename.

### Scraper Requirements

To set up the scraper, you'll need:

1. A Google account
2. Access to Google Sheets and Google Apps Script
3. Basic knowledge of how to open and use Google Sheets

### Scraper Setup Instructions

1. **Create a new Google Sheet** and name it whatever you prefer
2. **Add a sheet named "Data Udara"** inside the Google Sheet (this is where data will be stored)
3. **Open the Script Editor**:
   - Click on "Extensions" in the top menu
   - Select "Apps Script"
4. **Create three script files** in the Apps Script editor:
   - `Auto-Generate.gs` - Contains the main controller function
   - `Main-Code.gs` - Contains the data collection function
   - `Send-Email.gs` - Contains the email function
5. **Save all files**
6. **Set up a trigger** to run the script automatically:
   - In the Apps Script editor, click on the clock icon (Triggers)
   - Click "Add Trigger"
   - Set "Function to run" to `getUdaraJakarta`
   - Set "Time-driven" and choose "Day timer" with a frequency of your choice (the script has its own 2-day check)
   - Save the trigger

## Part 2: PM2.5 Interpolation Analysis

### What is PM2.5?

PM2.5 refers to tiny airborne particles less than 2.5 micrometers in diameter. These particles are small enough to penetrate deep into the lungs and even enter the bloodstream, posing significant health risks. Monitoring PM2.5 levels is crucial for understanding air quality and its impact on public health.

### What the Interpolation System Does

The interpolation analysis takes the point measurements collected by the scraper and:

1. Validates and processes the sensor data
2. Uses Inverse Distance Weighting (IDW) to estimate pollution levels for areas without sensors
3. Aggregates results to the kelurahan level (Jakarta's administrative sub-districts)
4. Produces a comprehensive dataset with PM2.5 estimates for all kelurahan at each timestamp

### Methodology: Inverse Distance Weighting (IDW)

IDW is a spatial interpolation technique that estimates values at unknown locations based on known measurements from surrounding points. The core principle is simple: locations closer to a measurement point are more influenced by its value than distant locations.

The PM2.5 value at an unmeasured location is calculated as:

```
Z(s₀) = Σ[wᵢ × Z(sᵢ)] / Σwᵢ
```

Where:
- Z(s₀) is the estimated PM2.5 value at the location we want to predict
- Z(sᵢ) is the known PM2.5 value at sensor location i
- wᵢ is the weight assigned to sensor i, calculated as 1/[distance]²
- Closer sensors have more influence on the estimated value
- As distance increases, influence decreases rapidly

### Interpolation Requirements

The interpolation analysis is implemented in R and requires:

```r
# Spatial data handling
library(sf)          # For spatial data handling
library(gstat)       # For IDW interpolation

# Data manipulation
library(dplyr)       # For data manipulation
library(lubridate)   # For datetime handling
library(tidyr)       # For data reshaping
library(haven)       # For importing/exporting Stata .dta files
library(stringr)     # For string manipulation
library(geosphere)   # For distance calculations in kilometers

# Parallelization
library(parallel)
library(foreach)
library(doParallel)
```

### Detailed Interpolation Process

The interpolation process follows these steps:

1. **Data Loading and Initial Setup**
   - Load sensor data from CSV files generated by the scraper
   - Set timezone to Jakarta (WIB)
   - Convert data formats (ensure numeric coordinates, PM2.5 values, etc.)

2. **Sensor Location Validation**
   - Check sensor coordinates against valid bounds for Jakarta
   - Valid longitude range: 106° to 107° E
   - Valid latitude range: -7° to -5.4° S (extended to include islands)
   - Exclude sensors with coordinates outside these bounds

3. **Reporting Frequency Analysis**
   - Determine how often each sensor reports (30-minute vs. hourly intervals)
   - Classify each sensor's reporting pattern based on timestamp patterns
   - Select the most appropriate time interval for analysis

4. **Timestamp Standardization**
   - Round all timestamps to either 30-minute or hourly intervals
   - Create a complete sequence of timestamps for the study period

5. **Temporal Interpolation**
   - Estimate missing values for sensors that report less frequently
   - Ensure all sensors have values at each timestamp being analyzed

6. **Data Completeness Verification**
   - Require at least 50 active sensors for a timestamp to be processed
   - Calculate coverage percentages and identify timestamps with sufficient data

7. **Spatial Grid Creation**
   - Create a grid of points covering all Jakarta kelurahan with a cell size of 0.005 degrees
   - This grid forms the basis for interpolation calculations

8. **IDW Interpolation**
   - For each grid point, use the 10 nearest sensors to estimate PM2.5 values
   - Apply the IDW formula with power parameter p=2
   - Track contributing sensors for each grid point

9. **Kelurahan-level Aggregation**
   - Determine which grid points fall within each kelurahan boundary
   - Calculate average PM2.5 value for each kelurahan based on contained grid points
   - Calculate minimum, maximum, and other statistics for each kelurahan

10. **Results Compilation and Storage**
    - Combine results from all successfully processed timestamps
    - Save the complete dataset in Stata (.dta) format
    - Generate summary statistics and reports

### Key Parameters and Assumptions

- **Coordinate bounds**: Longitude 106° to 107° E, Latitude -7° to -5.4° S
- **Grid cell size**: 0.005 degrees (approximately 550 meters)
- **Minimum sensors required**: 50 sensors must be active for a timestamp to be processed
- **Maximum points used**: 10 nearest sensors for each grid point
- **Power parameter**: p=2
- **Core assumption**: Nearby locations have similar PM2.5 values (proximity equals similarity)

## Integration Between Components

The output CSV files from the Data Collection System serve as input for the Interpolation Analysis. To ensure smooth integration:

1. The scraper emails CSV files with a consistent naming pattern that includes the date
2. These files can be collected and organized for batch processing by the R analysis script
3. The R script is designed to load and process multiple CSV files spanning different dates

## Setting Up the Complete System

### Step 1: Set up the Data Collection System
- Follow the scraper setup instructions in Part 1

### Step 2: Prepare for Data Transfer
- Create a folder structure to organize the CSV files received via email
- Consider setting up an automated process to download attachments from the designated email

### Step 3: Set up the Interpolation Analysis
- Install R and the required packages
- Prepare your spatial data (kelurahan boundaries for Jakarta)
- Adjust the R script to point to your CSV data directory

### Step 4: Schedule Regular Analysis
- Determine how frequently you want to run the interpolation analysis
- Set up a recurring schedule for running the R script (e.g., weekly)

## Project Limitations

1. **Data Availability**: The scraper can only collect data every 2 days, and only what's available on the official website.

2. **Interpolation Assumptions**: The IDW method assumes that proximity equals similarity and doesn't account for factors like wind patterns or elevation.

3. **Computational Resources**: The interpolation process is computationally intensive and may require significant processing time.

4. **Minimum Data Requirements**: Timestamps with fewer than 50 active sensors are excluded from analysis.

5. **Sensor Reliability**: The analysis assumes all sensor measurements are equally reliable.

## Applications and Future Development

This integrated system enables:
- Long-term air quality trend analysis for Jakarta
- Identification of pollution hotspots at the kelurahan level
- Correlation studies between air quality and health outcomes
- Development of targeted intervention strategies for high-pollution areas

Future development could include:
- Adding automated visualization tools
- Incorporating weather data to improve interpolation accuracy
- Creating a public-facing dashboard for real-time pollution estimates
- Extending the analysis to include other pollutants beyond PM2.5

## Credits and Contact

This project was developed to support environmental monitoring and public health research in Jakarta. For questions or collaboration opportunities, please contact [Your Contact Information].

## License

[Add appropriate license information here]
