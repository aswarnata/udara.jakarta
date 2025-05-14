# PM2.5 Data Collection and Interpolation System for Jakarta

## Project Overview

This project consists of two integrated components that work together to collect, process, and interpolate PM2.5 air quality data across Jakarta at the kelurahan level:

1. **Data Collection**: An automated scraper that collects high-frequency PM2.5 data from Jakarta's official air quality monitoring network
2. **Spatial Analysis**: An interpolation system that transforms point-based sensor measurements into pollution estimates for all Kelurahan in Jakarta

Together, these components create a complete workflow from raw data acquisition to detailed spatial analysis, enabling a comprehensive understanding of air pollution patterns across Jakarta.

## Why This Project Matters

High-quality, high-frequency, and extensive sensor networks are key for good air quality data. Jakarta's Environmental Agency (Dinas Lingkungan Hidup) provides excellent data with 30-minute and 1-hour interval readings of PM2.5 across 113 sensors throughout the city. This data is publicly accessible through their website.

However, there are two significant limitations that this project addresses:

1. **Data Persistence**: Historical data is only available for the past 2 days on the official website, with no published procedure to access older data. This necessitates automatic scraping to build a complete historical dataset.
   
2. **Spatial Coverage**: Air quality sensors only exist at specific locations, leaving many areas without direct measurements. Spatial interpolation is needed to estimate pollution levels for all kelurahan across Jakarta.
   
3. **Variable sensor coverage**: Not all sensors are active continuously; on some days, only 50% of the sensors in the network are operational.

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

The data collection function (`getUdaraJakartaData()`) connects to Jakarta's air quality API and fetches PM2.5 data from over all active monitoring stations throughout the city. It then organizes this data into a Google Sheet with columns for station ID, date, and PM2.5 value.

The email function (`kirimSheetSebagaiCSV()`) converts the Google Sheet data to CSV format and emails it to a designated recipient with the current date in the subject line and filename.

### Scraper Requirements

To set up the scraper, you'll need:

1. A Google account
2. Access to Google Sheets and Google Apps Script

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

### Software and Requirements

The interpolation analysis is implemented in R and requires the following packages:

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

The code includes automatic package management that checks for missing packages and installs them if needed, making the script more portable and easier to run on different systems.

### Methodology: Inverse Distance Weighting (IDW)

IDW is a spatial interpolation technique that estimates values at unknown locations based on known measurements from surrounding points. The core principle is simple: locations closer to a measurement point are more influenced by its value than distant locations.

The PM2.5 value at an unmeasured location is calculated as:

$$Z(s_0) = \frac{\sum_{i=1}^{n} w_i Z(s_i)}{\sum_{i=1}^{n} w_i}$$

Where:
- $Z(s_0)$ is the estimated PM2.5 value at the location we want to predict
- $Z(s_i)$ is the known PM2.5 value at sensor location $i$
- $w_i$ is the weight assigned to sensor $i$
- $n$ is the number of sensors used in the calculation (3 in our analysis)

The weights are calculated based on the distance between locations:

$$w_i = \frac{1}{d(s_0, s_i)^p}$$

Where:
- $d(s_0, s_i)$ is the distance between the prediction location and sensor location $i$
- $p$ is the power parameter (in our analysis, $p = 2$)

In simple terms, this means:
- Closer sensors have more influence on the estimated value
- As distance increases, influence decreases rapidly
- The power parameter (p=2) controls how quickly influence diminishes with distance

### Detailed Processing Steps

#### 1. Data Loading and Initial Setup
- Load sensor data from CSV files generated by the scraper
- Convert data formats (ensure numeric coordinates, PM2.5 values, etc.)

#### 2. Sensor Location Validation
- Check sensor coordinates against valid bounds for Jakarta (including Kepulauan Seribu)
- Valid longitude range: 106° to 107° E
- Valid latitude range: -7° to -5.4° S (extended to include islands north of Jakarta)
- **Exclude** any sensors with coordinates outside these bounds or with missing coordinates
- This approach maintains spatial integrity by only using sensors with confirmed valid locations

#### 3. Reporting Frequency Analysis
- The system analyzes each sensor's reporting pattern to determine its frequency characteristics
- For each sensor, it examines the timestamps when the sensor should report at half-hour marks (XX:30)
- Classification rules focus on how consistently a sensor reports at half-hour marks (XX:30):
  * **30-minute sensor**: If more than 70% of possible half-hour marks (XX:30) have valid PM2.5 readings, the sensor is classified as a "30-minute sensor." These sensors reliably report at both hour (XX:00) and half-hour (XX:30) intervals.
  * **Hourly sensor**: If less than 30% of possible half-hour marks (XX:30) have valid PM2.5 readings, the sensor is classified as an "hourly sensor." These sensors primarily report at hour marks (XX:00) only.
  * **Mixed sensor**: If 30-70% of possible half-hour marks (XX:30) have valid PM2.5 readings, the sensor is classified as having a "mixed" reporting pattern.
- Example: For a 24-hour period (with 24 possible half-hour timestamps):
  * A sensor with ≥17 readings at XX:30 times is classified as a "30-minute sensor"
  * A sensor with ≤7 readings at XX:30 times is classified as an "hourly sensor"
  * A sensor with 8-16 readings at XX:30 times is classified as a "mixed sensor"
- The system counts how many sensors fall into each category
- **Global time interval decision**: Based on which type is most common (30-minute vs. hourly sensors), the system decides whether to use 30-minute or hourly intervals for the entire analysis. This is a single decision applied to the whole dataset, not decided sensor-by-sensor.
- Different handling based on sensor type and interval decision:
  * When 30-minute intervals are used:
    * 30-minute sensors: Data is used as-is without interpolation (any occasional missing values remain missing)
    * Hourly and mixed sensors: Their missing half-hour values are selectively interpolated
  * When hourly intervals are used:
    * All sensors (30-minute, hourly, and mixed): Data is aggregated to hourly values

#### 4. Timestamp Standardization
- Round all timestamps to either 30-minute or hourly intervals based on the decision in step 3
- Create a complete sequence of timestamps for the study period

#### 5. Temporal Interpolation
When using 30-minute intervals, the analysis uses a more selective imputation strategy:
- For each hourly and mixed-frequency sensor, a complete set of 30-minute timestamps is created
- The imputation only focuses on half-hour marks (XX:30) that are missing PM2.5 values
- Imputation is only performed when both adjacent hourly readings exist (e.g., 10:00 and 11:00 for estimating 10:30)
- The imputed value is simply the average of the two adjacent hourly readings
- This more restrictive approach ensures that interpolation only occurs when there is strong evidence of values on both sides
- The selective imputation helps prevent unreliable estimates for large gaps or edge cases

#### 6. Data Completeness Verification
- For each timestamp, count how many sensors have valid PM2.5 readings
- Calculate coverage percentages and identify timestamps with sufficient data
- The analysis requires at least 50 active sensors for a timestamp to be processed
- This threshold is somewhat arbitrary but ensures sufficient spatial coverage

#### 7. Spatial Grid Creation
- Load kelurahan boundary data
- Create a grid of points covering all Jakarta kelurahan with a cell size of 0.005 degrees (approximately 550 meters)
- This grid forms the basis for interpolation calculations

#### 8. IDW Interpolation Process
For each valid timestamp (with at least 50 active sensors):
- Filter sensor data for the specific timestamp
- For each grid point:
  * Calculate distances to all active sensors
  * Identify the 3 nearest sensors that will contribute to this grid point's estimate (this number was optimized through sensitivity analysis)
  * Store the contributing sensor IDs for later analysis
- Apply the IDW formula to calculate PM2.5 values for each grid point using these 3 nearest sensors
- Power parameter (p) is set to 2, balancing local and distant influences

For representative timestamps (with maximum, minimum, and median sensor counts), the system also calculates distance metrics:
- Minimum distance to contributing sensors (in kilometers)
- Median distance to contributing sensors
- Average distance to contributing sensors
- Maximum distance to contributing sensors
These metrics help understand how far sensors are from the areas being interpolated.

#### 9. Spatial Interpolation and Aggregation Process
The process works in two distinct stages for each timestamp:

1. **Grid-level Interpolation**: 
   - First, PM2.5 values are estimated for each point in the predefined grid (at 0.005 degree spacing)
   - For each grid point, the IDW formula is applied using the 3 nearest sensor measurements
   - This creates a dense "field" of estimated PM2.5 values covering the entire Jakarta area

2. **Kelurahan-level Aggregation**:
   - The system determines which grid points fall within each kelurahan boundary
   - For each kelurahan, all grid points inside its boundary are identified
   - The PM2.5 values of these grid points are then:
     * Averaged to produce the mean PM2.5 value for the kelurahan
     * Analyzed to find minimum and maximum values within the kelurahan
     * Counted to determine how many grid points ("n_grids") contributed
   - The contributing sensors for each kelurahan are also tracked

This two-stage approach means that the final PM2.5 value for each kelurahan is effectively an area-weighted average based on the interpolated values across its geographic extent.

#### 10. Parallel Processing
- The interpolation for different timestamps is distributed across multiple CPU cores
- This significantly accelerates processing time for the computationally intensive task

#### 11. Results Compilation and Storage
- Combine results from all successfully processed timestamps
- Save the complete dataset in Stata (.dta) format
- Generate summary statistics and reports

### Key Parameters

- **Coordinate bounds**: Longitude 106° to 107° E, Latitude -7° to -5.4° S
- **Grid cell size**: 0.005 degrees (approximately 550 meters)
- **Minimum sensors required**: 50 sensors must be active throughout Jakarta for a timestamp to be processed (this threshold is somewhat arbitrary)
- **Maximum points used**: 3 nearest sensors for each grid point (optimized based on validation and sensitivity analysis)
- **Power parameter (p)**: 2
- **Parallel processing**: Uses all available CPU cores minus one
- **Distance metrics**: Calculated for three representative timestamps (with maximum, minimum, and median sensor counts)

### Results

The interpolation analysis produces two main output files:

1. **Primary PM2.5 Dataset** (Stata .dta format):
   - Kelurahan name
   - Timestamp (in Stata's milliseconds-since-1960 format)
   - Average PM2.5 value
   - Minimum and maximum PM2.5 values
   - Number of grid points used in the calculation (n_grids)
   - Number of sensors contributing to the estimate
   - Number of sensors used in the entire timestamp
   - The filename includes the nmax value used for the analysis (e.g., "jakarta_kelurahan_pm25_nmax3_2025-04-10_to_2025-05-10.dta")

2. **Distance Metrics Dataset** (separate Stata .dta file):
   - Kelurahan name
   - Timestamp type (maximum, minimum, or median sensor count)
   - PM2.5 values (average, minimum, maximum)
   - Minimum distance to contributing sensors (km)
   - Median distance to contributing sensors (km)
   - Average distance to contributing sensors (km)
   - Maximum distance to contributing sensors (km)
   - Number of grid points (n_grids)
   - Number of sensors used
   - Number of contributing sensors

These outputs enable understanding of air pollution patterns across Jakarta at a detailed administrative level, along with information about spatial representation and the relationship between sensor locations and interpolated areas.

### Performance Optimizations

Several optimizations improve the analysis efficiency:
- Increased grid cell size (0.005 degrees instead of 0.001)
- Using only 3 nearest points for interpolation (optimized through sensitivity analysis, reduced from initial 10-20)
- Parallel processing across multiple CPU cores
- Pre-computed interpolation grid
- Extended coordinate bounds to include Kepulauan Seribu (latitude range -7° to -5.4°)
- Automatic package management
- Selective distance calculation only for representative timestamps
- Improved selective half-hour imputation that only fills values with adjacent hourly readings
- Filtering timestamps with minimum sensor threshold before processing

### Key Assumptions and Limitations

1. **Proximity Equals Similarity**: The fundamental assumption of IDW is that locations closer to each other have more similar values than distant locations.

2. **No Directional Bias**: The basic IDW model doesn't account for directional effects such as wind patterns, which could influence pollution dispersion.

3. **Sensor Reliability**: All sensor measurements are assumed to be equally reliable.

4. **Selective Temporal Interpolation**: For sensors with hourly data or mixed reporting patterns (when using 30-minute intervals), values are only interpolated at half-hour marks (XX:30) when both adjacent hour readings (XX:00 and (XX+1):00) are available.

5. **Minimum Data Requirements**: The threshold of 50 sensors is somewhat arbitrary but ensures sufficient spatial coverage for reliable interpolation. Timestamps with fewer active sensors are excluded.

6. **Valid Coordinates Only**: Sensors with invalid or missing coordinates are completely excluded, which preserves spatial integrity but might reduce the available data.

7. **Parameter Selection**: The use of 3 nearest sensors (nmax=3) was determined through sensitivity analysis, balancing localized influence with sufficient data points.

## Integration Between Components

The output CSV files from the Data Collection System serve as input for the Interpolation Analysis. To ensure smooth integration:

1. The scraper emails CSV files with a consistent naming pattern that includes the date
2. These files can be collected and organized for batch processing by the R analysis script

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

### Step 4: Schedule Regular Analysis (Optional)
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
