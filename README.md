# PM2.5 Interpolation Analysis for Jakarta Kelurahan

## Overview

This document explains the process of interpolating PM2.5 (fine particulate matter) air pollution data across Jakarta's administrative divisions (kelurahan). The analysis takes point measurements from air quality sensors located throughout Jakarta and estimates pollution levels for areas without sensors.

## Software and Requirements

The analysis is implemented in R and requires the following packages:

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

## What is PM2.5?

PM2.5 refers to tiny airborne particles less than 2.5 micrometers in diameter. These particles are small enough to penetrate deep into the lungs and even enter the bloodstream, posing significant health risks. Monitoring PM2.5 levels is crucial for understanding air quality and its impact on public health.

## The Challenge

Air quality sensors are only available at specific locations, leaving many areas without direct measurements. To understand pollution patterns across the entire city, we need a method to estimate PM2.5 levels in locations without sensors.

## Methodology: Inverse Distance Weighting (IDW)

### What is IDW?

Inverse Distance Weighting is a spatial interpolation technique that estimates values at unknown locations based on known measurements from surrounding points. The core principle is simple: locations closer to a measurement point are more influenced by its value than distant locations.

### The IDW Formula

The PM2.5 value at an unmeasured location is calculated as:

$Z(s_0) = \frac{\sum_{i=1}^{n} w_i Z(s_i)}{\sum_{i=1}^{n} w_i}$

Where:
- $Z(s_0)$ is the estimated PM2.5 value at the location we want to predict
- $Z(s_i)$ is the known PM2.5 value at sensor location $i$
- $w_i$ is the weight assigned to sensor $i$
- $n$ is the number of sensors used in the calculation (10 in our analysis)

The weights are calculated based on the distance between locations:

$w_i = \frac{1}{d(s_0, s_i)^p}$

Where:
- $d(s_0, s_i)$ is the distance between the prediction location and sensor location $i$
- $p$ is the power parameter (in our analysis, $p = 2$)

In simple terms, this means:
- Closer sensors have more influence on the estimated value
- As distance increases, influence decreases rapidly
- The power parameter (p=2) controls how quickly influence diminishes with distance

## Data Sources

The analysis uses two primary data sources:
1. **PM2.5 Sensor Data**: Measurements from air quality monitoring stations across Jakarta, including:
   - Sensor ID
   - Location (latitude and longitude)
   - Timestamp
   - PM2.5 measurement

2. **Kelurahan Boundaries**: Geographic boundaries of Jakarta's administrative divisions

## Detailed Processing Steps

### 1. Data Loading and Initial Setup
- Load sensor data from Stata (.dta) file
- Set timezone to Jakarta (WIB)
- Convert data formats (ensure numeric coordinates, PM2.5 values, etc.)

### 2. Sensor Location Validation
- Check sensor coordinates against valid bounds for Jakarta (including Kepulauan Seribu)
- Valid longitude range: 106° to 107° E
- Valid latitude range: -7° to -5.4° S (extended to include islands north of Jakarta)
- **Exclude** any sensors with coordinates outside these bounds or with missing coordinates
- This approach maintains spatial integrity by only using sensors with confirmed valid locations

### 3. Reporting Frequency Analysis
- The system needs to determine how often each sensor reports data - some report every 30 minutes, others only once per hour
- For each sensor, the analysis examines whether it consistently reports at half-hour marks (e.g., 10:30, 11:30)
- Classification rules:
  * **30-minute sensor**: If a sensor has data for more than 70% of half-hour timestamps (like 10:30, 11:30), it's classified as reporting every 30 minutes
  * **Hourly sensor**: If a sensor has data for less than 30% of half-hour timestamps, it's classified as reporting only at full hours (like 10:00, 11:00)
  * **Mixed sensor**: Sensors with half-hour data between 30-70% of the time are explicitly classified as having mixed or inconsistent reporting patterns
- The system counts and logs how many sensors fall into each category
- **Global time interval decision**: The system compares the total count of 30-minute sensors vs. hourly sensors. If more sensors report at 30-minute intervals, the entire analysis uses 30-minute intervals. Otherwise, it uses hourly intervals. This is a single decision applied to the whole dataset, not decided sensor-by-sensor.
- **Note about mixed sensors**: The handling of mixed sensors depends on which time interval is chosen:
  * If 30-minute intervals are used: Mixed sensors are excluded. Only clearly classified 30-minute and hourly sensors are processed (with hourly sensors getting interpolated values for half-hour marks).
  * If hourly intervals are used: All sensors (including mixed) are included, with their data aggregated to hourly values.

### 4. Timestamp Standardization
- Round all timestamps to either 30-minute intervals or hourly intervals based on the decision in step 3
- For example, 10:23 might be rounded to 10:30 in a 30-minute interval system

### 5. Temporal Interpolation
When using 30-minute intervals, the analysis uses a more selective imputation strategy:
- For each hourly and mixed-frequency sensor, a complete set of 30-minute timestamps is created
- The imputation only focuses on half-hour marks (XX:30) that are missing PM2.5 values
- Imputation is only performed when both adjacent hourly readings exist (e.g., 10:00 and 11:00 for estimating 10:30)
- The imputed value is simply the average of the two adjacent hourly readings
- This more restrictive approach ensures that interpolation only occurs when there is strong evidence of values on both sides
- The selective imputation helps prevent unreliable estimates for large gaps or edge cases

### 6. Data Completeness Verification
- For each timestamp, count how many sensors have valid PM2.5 readings
- Calculate coverage percentages and identify timestamps with insufficient data
- The analysis requires at least 50 active sensors throughout Jakarta for a timestamp to be processed

### 7. Spatial Grid Creation
- Load kelurahan boundary data
- Create a grid of points covering all Jakarta kelurahan with a cell size of 0.005 degrees (approximately 550 meters)
- This grid forms the basis for interpolation calculations

### 8. IDW Interpolation Process
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

### 9. Spatial Interpolation and Aggregation Process

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

### 10. Parallel Processing
- The interpolation for different timestamps is distributed across multiple CPU cores
- This significantly accelerates processing time for the computationally intensive task

### 11. Results Compilation and Storage
- Combine results from all successfully processed timestamps
- Save the complete dataset in Stata (.dta) format
- Generate summary statistics and reports

## Key Parameters

- **Coordinate bounds**: Longitude 106° to 107° E, Latitude -7° to -5.4° S
- **Grid cell size**: 0.005 degrees (approximately 550 meters)
- **Minimum sensors required**: 50 sensors must be active throughout Jakarta for a timestamp to be processed (this threshold is somewhat arbitrary)
- **Maximum points used**: 3 nearest sensors for each grid point (optimized based on validation and sensitivity analysis)
- **Power parameter (p)**: 2
- **Parallel processing**: Uses all available CPU cores minus one
- **Distance metrics**: Calculated for three representative timestamps (with maximum, minimum, and median sensor counts)

## Key Assumptions and Limitations

1. **Proximity Equals Similarity**: The fundamental assumption of IDW is that locations closer to each other have more similar values than distant locations.

2. **No Directional Bias**: The basic IDW model doesn't account for directional effects such as wind patterns, which could influence pollution dispersion.

3. **Sensor Reliability**: All sensor measurements are assumed to be equally reliable.

4. **Selective Temporal Interpolation**: For sensors with hourly data or mixed reporting patterns (when using 30-minute intervals), values are only interpolated at half-hour marks (XX:30) when both adjacent hour readings (XX:00 and (XX+1):00) are available.

5. **Minimum Data Requirements**: The threshold of 50 sensors is somewhat arbitrary but ensures sufficient spatial coverage for reliable interpolation. Timestamps with fewer active sensors are excluded.

6. **Valid Coordinates Only**: Sensors with invalid or missing coordinates are completely excluded, which preserves spatial integrity but might reduce the available data.

7. **Parameter Selection**: The use of 3 nearest sensors (nmax=3) was determined through sensitivity analysis, balancing localized influence with sufficient data points.

## Performance Optimizations

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

## Results

The analysis produces two main output files:

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

## Replication Guide

To replicate this analysis:

1. **Prepare your environment**:
   - Install R and the required packages listed in the Software and Requirements section
   - Prepare your sensor data in Stata (.dta) format with columns for sensor_id, datetime, latitude, longitude, and pm25
   - Obtain a shapefile with kelurahan boundaries for Jakarta

2. **Adjust parameters as needed**:
   - Modify coordinate bounds if your study area differs
   - Consider adjusting the minimum sensor threshold based on your data density
   - You may need to adjust the grid cell size based on your computational resources

3. **Run the analysis**:
   - The process is computationally intensive and may take several hours depending on your dataset size
   - Ensure you have sufficient disk space for storing intermediate and final results
   - Monitor the log file for any errors or warnings during processing

4. **Interpret results**:
   - Remember that interpolated values are estimates and should be interpreted with appropriate caution
   - Areas far from any sensors will have less reliable estimates
   - Consider visualizing uncertainty alongside the PM2.5 estimates when presenting results
