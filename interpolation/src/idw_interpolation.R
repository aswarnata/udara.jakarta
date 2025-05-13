#===============================================================================
# PARALLEL PROCESSING SETUP
#===============================================================================
# Step 9: Process all timestamps with parallelization
cat("\nBeginning IDW interpolation for all timestamps using parallel processing...\n")

# Using reduced nmax for better performance
min_sensors_to_use <- 50  # 50 sensors must active trhoughout Jakarta at given time for the calculation to proceed
nmax_points_to_use <- 10  # Each grid is contributed by maximum 10 nearest sensors

cat("Using parameters: min_sensors =", min_sensors_to_use, ", nmax =", nmax_points_to_use,
    "(nearest points), idp_power =", 2, "\n")
#===============================================================================
# PACKAGE MANAGEMENT - Install required packages if not already installed
#===============================================================================
# List of required packages
required_packages <- c("sf", "gstat", "dplyr", "lubridate", "tidyr", "haven", 
                       "stringr", "geosphere", "parallel", "foreach", "doParallel")

# Check which packages are not installed
not_installed <- required_packages[!required_packages %in% installed.packages()[,"Package"]]

# Install missing packages
if(length(not_installed) > 0) {
  cat("Installing missing packages:", paste(not_installed, collapse = ", "), "\n")
  install.packages(not_installed, repos = "https://cran.rstudio.com/")
}

# Required packages
library(sf)          # For spatial data handling
library(gstat)       # For IDW interpolation
library(dplyr)       # For data manipulation
library(lubridate)   # For datetime handling
library(tidyr)       # For data reshaping
library(haven)       # For importing Stata .dta files
library(stringr)     # For string manipulation
library(geosphere)   # For distance calculations in kilometers
# For parallelization
library(parallel)
library(foreach)
library(doParallel)

#===============================================================================
# DIRECTORY CONFIGURATION
#===============================================================================
# Set the base directory - this is the existing base path used in the script
base_dir <- "/Users/aryaswarnata/Library/CloudStorage/OneDrive-Personal/WBG/Air Pollution/data/aqi_dlh_jak"

# Create a directory structure based on existing paths
dirs <- list(
  base = base_dir,
  log = file.path(base_dir, "log"),
  processed = file.path(base_dir, "processed"),
  output = file.path(base_dir, "output"),
  shp = file.path(base_dir, "shp")
)

# Create directories if they don't exist
for (dir in dirs) {
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
    cat("Created directory:", dir, "\n")
  }
}

#===============================================================================
# SET UP LOGGING
#===============================================================================
log_file <- file.path(dirs$log, paste0("pm25_interpolation_log_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".txt"))

# Start logging
sink(log_file, append = FALSE, split = TRUE)  # 'split = TRUE' sends output to both console and file

#===============================================================================
# DATA LOADING
#===============================================================================
# Step 1: Load your sensor data from Stata .dta file
input_file <- file.path(dirs$processed, "pm25_jakarta_2025-04-10_to_2025-05-10.dta")
cat("\nLoading sensor data from:", input_file, "\n")

# Extract date from input filename to append to output files
date_pattern <- str_extract(basename(input_file), "\\d{4}-\\d{2}-\\d{2}(_to_\\d{4}-\\d{2}-\\d{2})?")
if(is.na(date_pattern)) {
  date_suffix <- ""
} else {
  date_suffix <- paste0("_", date_pattern)
}

sensors <- read_dta(input_file)
cat("Successfully loaded data with", nrow(sensors), "records\n")

#===============================================================================
# DATA CLEANING
#===============================================================================
# Step 2: Check and clean data formats
# Set the timezone attribute to Jakarta (WIB)
attr(sensors$datetime, "tzone") <- "Asia/Jakarta"

# Ensure numeric formats for coordinates and PM2.5
sensors <- sensors %>%
  mutate(
    longitude = as.numeric(longitude),
    latitude = as.numeric(latitude),
    pm25 = as.numeric(pm25),
    sensor_id = as.character(sensor_id)
  )

# Flag invalid coordinates using updated bounds to include Kepulauan Seribu
invalid_coords <- sensors %>%
  filter(is.na(longitude) | is.na(latitude) |
           longitude < 106 | longitude > 107 |     # Longitude bounds remain the same
           latitude < -7 | latitude > -5.4)        # Extended upper bound to include islands north of Jakarta

if(nrow(invalid_coords) > 0) {
  cat("Found", nrow(invalid_coords), "records with invalid coordinates that will be excluded\n")
  
  # Get count of excluded sensors
  excluded_sensors <- n_distinct(invalid_coords$sensor_id)
  total_sensors <- n_distinct(sensors$sensor_id)
  
  cat("Excluding", excluded_sensors, "sensors out of", total_sensors,
      "(", round(100 * excluded_sensors / total_sensors, 1), "% of sensors)\n")
  
  # EXCLUDE records with invalid coordinates instead of replacing them
  sensors <- sensors %>%
    filter(!(is.na(longitude) | is.na(latitude) |
               longitude < 106 | longitude > 107 |
               latitude < -7 | latitude > -5.4))
  
  cat("After excluding invalid coordinates,", nrow(sensors), "records remain\n")
} else {
  cat("No records with invalid coordinates found using Jakarta bounds including Kepulauan Seribu\n")
}

# Count PM2.5 data availability
pm25_stats <- sensors %>%
  summarize(
    total_records = n(),
    valid_pm25 = sum(!is.na(pm25)),
    percent_valid = round(100 * sum(!is.na(pm25)) / n(), 1)
  )

cat("\nPM2.5 data availability:\n")
print(pm25_stats)

#===============================================================================
# FREQUENCY ANALYSIS
#===============================================================================
# Step 3: Analyze data frequency patterns
# For each sensor, determine its reporting frequency
sensor_frequency <- sensors %>%
  group_by(sensor_id) %>%
  mutate(is_half_hour = minute(datetime) == 30) %>%
  summarize(
    total_readings = n(),
    half_hour_readings = sum(is_half_hour),
    half_hour_valid = sum(is_half_hour & !is.na(pm25)),
    full_hour_valid = sum(!is_half_hour & !is.na(pm25)),
    half_hour_valid_ratio = ifelse(half_hour_readings > 0, 
                                   half_hour_valid / half_hour_readings,
                                   0),
    is_30min = half_hour_valid_ratio > 0.7,  # If >70% of half-hour timestamps have data
    is_hourly = half_hour_valid_ratio < 0.3,  # If <30% of half-hour timestamps have data
    is_mixed = half_hour_valid_ratio >= 0.3 & half_hour_valid_ratio <= 0.7, # Mixed frequency pattern
    .groups = "drop"
  )

# Print summary of sensor frequency patterns
frequency_summary <- sensor_frequency %>%
  summarize(
    count_30min = sum(is_30min),
    count_hourly = sum(is_hourly),
    count_mixed = sum(is_mixed),
    count_other = sum(!is_30min & !is_hourly & !is_mixed),
    total_sensors = n()
  )

cat("\nSensor frequency patterns summary:\n")
print(frequency_summary)
cat("Found", frequency_summary$count_mixed, "sensors with mixed/inconsistent reporting frequency\n")

#===============================================================================
# TIME INTERVAL SELECTION
#===============================================================================
# Step 4: Determine the target time intervals for interpolation
# Decide whether to use 30-min or hourly intervals based on sensor distribution
use_30min_intervals <- frequency_summary$count_30min > frequency_summary$count_hourly

if(use_30min_intervals) {
  cat("\nUsing 30-minute intervals for interpolation (majority of sensors report at this frequency)\n")
} else {
  cat("\nUsing hourly intervals for interpolation (majority of sensors report at this frequency)\n")
}

# Step 5: Standardize timestamps to chosen interval
# Round timestamps to nearest hour or half-hour based on decision
if(use_30min_intervals) {
  # Round to nearest 30 minutes
  sensors <- sensors %>%
    mutate(
      rounded_datetime = round_date(datetime, unit = "30 mins")
    )
} else {
  # Round to nearest hour
  sensors <- sensors %>%
    mutate(
      rounded_datetime = round_date(datetime, unit = "hour")
    )
}

#===============================================================================
# INTERPOLATION HELPER FUNCTION
#===============================================================================
# Define helper function for interpolation
interpolate_sensor <- function(df) {
  # Sort by time
  df <- df %>% arrange(rounded_datetime)
  
  # For columns that need to be filled
  for(col in c("longitude", "latitude", "pm25")) {
    if(all(is.na(df[[col]]))) next  # Skip if all values are NA
    
    # Try linear interpolation first (works for numeric values)
    if(col == "pm25") {
      df[[col]] <- approx(
        x = as.numeric(df$rounded_datetime[!is.na(df[[col]])]), 
        y = df[[col]][!is.na(df[[col]])],
        xout = as.numeric(df$rounded_datetime),
        method = "linear",
        rule = 2  # Rule 2 uses nearest value extrapolation for ends
      )$y
    } else {
      # For coordinates, just fill forward/backward as they shouldn't change
      # Find nearest non-NA value
      na_indices <- which(is.na(df[[col]]))
      if(length(na_indices) > 0) {
        for(i in na_indices) {
          nearest_idx <- which(!is.na(df[[col]]))
          if(length(nearest_idx) > 0) {
            nearest <- nearest_idx[which.min(abs(nearest_idx - i))]
            df[[col]][i] <- df[[col]][nearest]
          }
        }
      }
    }
  }
  return(df)
}

#===============================================================================
# HANDLE MIXED FREQUENCY DATA
#===============================================================================
# Step 6: For sensors with hourly data or mixed patterns when using 30-min intervals, handle the missing half-hour data
if(use_30min_intervals) {
  # Identify hourly sensors (to fill in their missing 30-min readings)
  hourly_sensors <- sensor_frequency %>%
    filter(is_hourly) %>%
    pull(sensor_id)
  
  # Identify mixed sensors that should also have missing timestamps interpolated
  mixed_sensors <- sensor_frequency %>%
    filter(is_mixed) %>%
    pull(sensor_id)
  
  # Combine hourly and mixed sensors for interpolation
  sensors_to_interpolate <- c(hourly_sensors, mixed_sensors)
  
  cat("Found", length(hourly_sensors), "hourly sensors and", length(mixed_sensors), 
      "mixed sensors that need interpolation\n")
  
  # Get all unique rounded timestamps - ensure we have all half-hour marks
  all_timestamps <- unique(sensors$rounded_datetime)
  
  # Ensure we have both hour and half-hour timestamps for complete interpolation
  start_time <- min(all_timestamps)
  end_time <- max(all_timestamps)
  
  # Generate complete sequence of 30-min timestamps
  complete_timestamps <- seq(from = start_time, to = end_time, by = "30 min")
  all_timestamps <- sort(unique(c(all_timestamps, complete_timestamps)))
  
  cat("Total unique timestamps after ensuring all half-hours:", length(all_timestamps), "\n")
  
  # For sensors that need interpolation, use the closest available reading for missing timestamps
  interpolated_readings <- data.frame()
  
  for(sensor_id in sensors_to_interpolate) {
    # Get data for this sensor
    sensor_data <- sensors %>%
      filter(sensor_id == !!sensor_id) %>%
      select(sensor_id, longitude, latitude, rounded_datetime, pm25) %>%
      arrange(rounded_datetime)
    
    # Create data frame with all timestamps for this sensor
    sensor_full <- data.frame(
      sensor_id = sensor_id,
      rounded_datetime = all_timestamps
    )
    
    # Join with existing data and forward/backward fill missing values
    sensor_filled <- sensor_full %>%
      left_join(sensor_data, by = c("sensor_id", "rounded_datetime"))
    
    # Apply interpolation
    sensor_filled <- interpolate_sensor(sensor_filled)
    
    # Add to our collection
    interpolated_readings <- bind_rows(interpolated_readings, sensor_filled)
  }
  
  # Combine with original data
  # First, get the 30-min sensor data that doesn't need interpolation
  sensors_30min <- sensors %>%
    filter(sensor_id %in% sensor_frequency$sensor_id[sensor_frequency$is_30min]) %>%
    select(sensor_id, longitude, latitude, rounded_datetime, pm25)
  
  # Exclude sensors that have already been interpolated
  # We no longer need the original mixed sensor data as it's been interpolated
  remaining_sensors <- sensors %>%
    filter(!(sensor_id %in% sensors_to_interpolate) & 
             !(sensor_id %in% sensor_frequency$sensor_id[sensor_frequency$is_30min])) %>%
    select(sensor_id, longitude, latitude, rounded_datetime, pm25)
  
  # Combine all original readings with interpolated data
  combined_data <- bind_rows(
    sensors_30min,
    remaining_sensors
  )
  
  # Safe alternative to anti_join - find missing rows
  if(nrow(interpolated_readings) > 0) {
    # Create keys for each dataset
    combined_keys <- paste(combined_data$sensor_id, combined_data$rounded_datetime, sep = "_")
    interpolated_keys <- paste(interpolated_readings$sensor_id, interpolated_readings$rounded_datetime, sep = "_")
    
    # Find keys that exist in interpolated_readings but not in combined_data
    missing_keys <- setdiff(interpolated_keys, combined_keys)
    
    if(length(missing_keys) > 0) {
      # Extract the missing rows
      missing_indices <- which(paste(interpolated_readings$sensor_id, 
                                     interpolated_readings$rounded_datetime, sep = "_") %in% missing_keys)
      missing_interpolated <- interpolated_readings[missing_indices, ]
      
      # Final combined dataset
      sensors_processed <- bind_rows(combined_data, missing_interpolated)
    } else {
      sensors_processed <- combined_data
    }
  } else {
    sensors_processed <- combined_data
  }
} else {
  # Using hourly intervals - simpler case
  # Just aggregate to hourly data for all sensors
  cat("Using hourly intervals - aggregating all sensors to hourly data\n")
  sensors_processed <- sensors %>%
    group_by(sensor_id, rounded_datetime) %>%
    summarize(
      pm25 = mean(pm25, na.rm = TRUE),
      longitude = first(na.omit(longitude)),
      latitude = first(na.omit(latitude)),
      .groups = "drop"
    )
}

#===============================================================================
# DATA COMPLETENESS CHECK
#===============================================================================
# Step 7: Check data completeness after processing
processed_availability <- sensors_processed %>%
  group_by(rounded_datetime) %>%
  summarize(
    available_sensors = sum(!is.na(pm25)),
    total_sensors = n_distinct(sensor_id),
    coverage_percent = round(100 * available_sensors / total_sensors, 1),
    .groups = "drop"
  )

# Print summary of processed data
processed_summary <- processed_availability %>%
  summarize(
    min_coverage = min(coverage_percent),
    max_coverage = max(coverage_percent),
    avg_coverage = mean(coverage_percent),
    timestamps_below_50pct = sum(coverage_percent < 50)
  )

cat("\nData availability after processing:\n")
print(processed_summary)

#===============================================================================
# LOAD GEOGRAPHICAL BOUNDARIES
#===============================================================================
# Step 8: Load Jakarta kelurahan boundaries
cat("\nLoading Jakarta kelurahan boundaries...\n")
tryCatch({
  # Path to your shapefile - using the organized directory structure
  kelurahan <- st_read(file.path(dirs$shp, "jakarta_kelurahan_combined.shp"), quiet = TRUE)
  cat("Successfully loaded shapefile with", nrow(kelurahan), "kelurahan\n")
  
  # Try to identify the name field
  potential_name_fields <- c("KELURAHAN_NAME", "NAMOBJ", "NAMA", "DESA", "NAME", "KELURAHAN")
  kelurahan_name_field <- NULL
  
  for(field in potential_name_fields) {
    if(field %in% names(kelurahan)) {
      kelurahan_name_field <- field
      cat("Using", field, "as the kelurahan name field\n")
      break
    }
  }
  
  if(is.null(kelurahan_name_field)) {
    cat("WARNING: No standard kelurahan name field found in shapefile\n")
    # If no name field found, use the first character field
    char_fields <- names(kelurahan)[sapply(kelurahan, is.character)]
    if(length(char_fields) > 0) {
      kelurahan_name_field <- char_fields[1]
      cat("Using", kelurahan_name_field, "as the kelurahan name field (first character field)\n")
    } else {
      kelurahan$KELURAHAN_NAME <- paste("Kelurahan", 1:nrow(kelurahan))
      kelurahan_name_field <- "KELURAHAN_NAME"
      cat("Created sequential kelurahan names\n")
    }
  }
}, error = function(e) {
  cat("ERROR: Failed to load kelurahan boundaries:", e$message, "\n")
  cat("Attempting to proceed without boundaries...\n")
  # Create a simple rectangular boundary for Jakarta as fallback
  kelurahan <- st_sf(
    geometry = st_sfc(st_polygon(list(rbind(
      c(106.7, -6.4), c(107.0, -6.4), c(107.0, -5.4), c(106.7, -5.4), c(106.7, -6.4)
    )))),
    NAMOBJ = "JAKARTA",
    crs = 4326
  )
  kelurahan_name_field <- "NAMOBJ"
})

#===============================================================================
# PREPARE SPATIAL DATA
#===============================================================================
# Convert sensor data to spatial points
cat("\nConverting sensor data to spatial points...\n")
# Only filter out missing PM2.5
sensors_clean <- sensors_processed %>% 
  filter(!is.na(pm25))  # Keep all valid PM2.5 readings

# Create spatial points object
sensor_points <- st_as_sf(sensors_clean, coords = c("longitude", "latitude"), crs = 4326)
cat("Successfully created spatial points object with", nrow(sensor_points), "points\n")

# Make sure both datasets use the same CRS
kelurahan <- st_transform(kelurahan, st_crs(sensor_points))

# Create interpolation grid with larger cell size for better performance
cat("\nCreating interpolation grid...\n")
# Increase grid cell size from 0.001 to 0.005 for better performance
interpolation_grid <- st_make_grid(kelurahan, cellsize = 0.005, what = "centers") %>% 
  st_as_sf() %>%
  st_filter(kelurahan)
cat("Created interpolation grid with", nrow(interpolation_grid), "points\n")

#===============================================================================
# IDW INTERPOLATION FUNCTION
#===============================================================================
# Function to perform IDW for a single time period with tracking of contributing sensors and distances
perform_idw_for_timepoint <- function(data, time_value, kelurahan_boundaries, grid,
                                      kelurahan_name_field = "NAMOBJ",
                                      min_sensors = 3, nmax_points = 15,
                                      idp_power = 2, 
                                      calculate_distances = FALSE,
                                      representative_timestamps = NULL) {
  # Filter data for this specific time
  data_at_time <- data %>% filter(rounded_datetime == time_value)
  
  # Check if we have enough sensors for reliable interpolation
  if(nrow(data_at_time) < min_sensors) {
    cat("Too few sensors available at", format(time_value, "%Y-%m-%d %H:%M:%S"), "- found", nrow(data_at_time), 
        "sensors, need at least", min_sensors, "\n")
    return(NULL)
  }
  
  # For each grid point, track which sensors contribute and their distances
  # Extract coordinates
  sensor_coords <- st_coordinates(data_at_time)
  grid_coords <- st_coordinates(grid)
  sensor_ids <- data_at_time$sensor_id
  
  # Pre-allocate lists to store contributing sensors for each grid point
  grid_contributing_sensors <- vector("list", nrow(grid))
  
  # Only calculate distances for representative timestamps
  is_representative <- FALSE
  if(!is.null(representative_timestamps)) {
    is_representative <- time_value %in% representative_timestamps
  }
  
  # Initialize distance variables
  grid_min_distances <- NULL
  grid_median_distances <- NULL
  grid_avg_distances <- NULL
  grid_max_distances <- NULL
  
  # Define Haversine formula function to calculate distances in km (as backup if geosphere fails)
  haversine_distance <- function(lon1, lat1, lon2, lat2) {
    # Convert degrees to radians
    lon1 <- lon1 * pi / 180
    lat1 <- lat1 * pi / 180
    lon2 <- lon2 * pi / 180
    lat2 <- lat2 * pi / 180
    
    # Haversine formula
    dlon <- lon2 - lon1
    dlat <- lat2 - lat1
    a <- sin(dlat/2)^2 + cos(lat1) * cos(lat2) * sin(dlon/2)^2
    c <- 2 * atan2(sqrt(a), sqrt(1-a))
    
    # Earth radius in kilometers
    R <- 6371
    
    # Distance in kilometers
    d <- R * c
    return(d)
  }
  
  # Only calculate distances if requested and this is a representative timestamp
  if(calculate_distances && is_representative) {
    # Pre-allocate distance arrays
    grid_min_distances <- numeric(nrow(grid))
    grid_median_distances <- numeric(nrow(grid))
    grid_avg_distances <- numeric(nrow(grid))
    grid_max_distances <- numeric(nrow(grid))
    
    cat("Calculating distances for representative timestamp:", format(time_value, "%Y-%m-%d %H:%M:%S"), "\n")
  }
  
  # For each grid point, find contributing sensors based on distance
  for(i in 1:nrow(grid)) {
    # Calculate distances to all sensors
    distances <- sqrt((grid_coords[i,1] - sensor_coords[,1])^2 +
                        (grid_coords[i,2] - sensor_coords[,2])^2)
    
    # Sort sensors by distance
    sorted_indices <- order(distances)
    
    # Take only the nearest nmax_points sensors
    if(length(sorted_indices) > nmax_points) {
      nearest_indices <- sorted_indices[1:nmax_points]
      nearest_distances <- distances[nearest_indices]
    } else {
      nearest_indices <- sorted_indices
      nearest_distances <- distances[nearest_indices]
    }
    
    # Store the IDs of contributing sensors for this grid point
    grid_contributing_sensors[[i]] <- sensor_ids[nearest_indices]
    
    # Calculate and store distance metrics if required
    if(calculate_distances && is_representative) {
      # Calculate kilometers using Haversine formula for the nearest points
      distances_km <- numeric(length(nearest_indices))
      
      # Try to use geosphere first
      tryCatch({
        grid_point <- c(grid_coords[i,1], grid_coords[i,2])
        for(j in 1:length(nearest_indices)) {
          idx <- nearest_indices[j]
          sensor_point <- c(sensor_coords[idx,1], sensor_coords[idx,2])
          # Calculate distance in meters and convert to kilometers
          distances_km[j] <- distGeo(grid_point, sensor_point) / 1000
        }
      }, error = function(e) {
        # Fall back to Haversine if geosphere fails
        for(j in 1:length(nearest_indices)) {
          idx <- nearest_indices[j]
          distances_km[j] <- haversine_distance(
            grid_coords[i,1], grid_coords[i,2],
            sensor_coords[idx,1], sensor_coords[idx,2]
          )
        }
      })
      
      # Store distance metrics in kilometers
      grid_min_distances[i] <- min(distances_km)
      grid_median_distances[i] <- median(distances_km)
      grid_avg_distances[i] <- mean(distances_km)
      grid_max_distances[i] <- max(distances_km)
    }
  }
  
  # Now perform the actual IDW
  idw_model <- gstat(formula = pm25 ~ 1, locations = data_at_time,
                     nmax = nmax_points,
                     set = list(idp = idp_power))
  
  # Perform prediction on the pre-computed grid
  tryCatch({
    idw_pred <- predict(idw_model, newdata = grid)
    
    # Convert predictions to spatial points
    idw_points <- st_as_sf(idw_pred)
    
    # Add contributing sensors info to predictions
    idw_points$contributing_sensors <- grid_contributing_sensors
    
    # Add distance metrics if calculated
    if(calculate_distances && is_representative) {
      idw_points$min_distance <- grid_min_distances
      idw_points$median_distance <- grid_median_distances
      idw_points$avg_distance <- grid_avg_distances
      idw_points$max_distance <- grid_max_distances
    }
    
    # Find which polygon each point belongs to
    point_poly_indices <- st_within(idw_points, kelurahan_boundaries, sparse = TRUE)
    
    # Prepare data for aggregation - include timestamp reference
    point_poly_data <- data.frame(
      point_index = 1:nrow(idw_points),
      poly_index = sapply(point_poly_indices, function(x) if(length(x) > 0) x[1] else NA),
      pm25_value = idw_points$var1.pred,
      timestamp_type = if(is_representative) {
        ifelse(time_value == representative_timestamps[1], "max_sensors",
               ifelse(time_value == representative_timestamps[2], "min_sensors", "median_sensors"))
      } else {
        "regular"
      }
    )
    
    # Add distance metrics if calculated
    if(calculate_distances && is_representative) {
      point_poly_data$min_distance <- idw_points$min_distance
      point_poly_data$median_distance <- idw_points$median_distance
      point_poly_data$avg_distance <- idw_points$avg_distance
      point_poly_data$max_distance <- idw_points$max_distance
    }
    
    # Add contributing sensors
    point_poly_data$contributing_sensors <- grid_contributing_sensors
    
    # Filter out points that don't fall within any polygon
    point_poly_data <- point_poly_data %>% filter(!is.na(poly_index))
    
    # Add kelurahan names to the point data
    point_poly_data$kelurahan_name <- kelurahan_boundaries[[kelurahan_name_field]][point_poly_data$poly_index]
    
    # Function to count unique contributing sensors per kelurahan
    count_unique_sensors <- function(sensor_lists) {
      unique_sensors <- unique(unlist(sensor_lists))
      return(length(unique_sensors))
    }
    
    # Define summarize function that adapts to whether distance metrics are available
    if(calculate_distances && is_representative) {
      # With distance metrics
      kelurahan_summary <- point_poly_data %>%
        group_by(kelurahan_name, timestamp_type) %>%
        summarize(
          avg_pm25 = mean(pm25_value, na.rm = TRUE),
          min_pm25 = min(pm25_value, na.rm = TRUE),
          max_pm25 = max(pm25_value, na.rm = TRUE),
          min_distance = mean(min_distance, na.rm = TRUE),
          median_distance = mean(median_distance, na.rm = TRUE),
          avg_distance = mean(avg_distance, na.rm = TRUE),
          max_distance = mean(max_distance, na.rm = TRUE),
          n_points = n(),
          n_sensors_used = nrow(data_at_time),
          n_contributing_sensors = count_unique_sensors(contributing_sensors),
          # Properly convert POSIXct to Stata's %tc format (milliseconds since 01jan1960)
          timestamp = (as.numeric(as.POSIXct(time_value)) + 315619200) * 1000,
          .groups = "drop"
        )
    } else {
      # Without distance metrics
      kelurahan_summary <- point_poly_data %>%
        group_by(kelurahan_name) %>%
        summarize(
          avg_pm25 = mean(pm25_value, na.rm = TRUE),
          min_pm25 = min(pm25_value, na.rm = TRUE),
          max_pm25 = max(pm25_value, na.rm = TRUE),
          n_points = n(),
          n_sensors_used = nrow(data_at_time),
          n_contributing_sensors = count_unique_sensors(contributing_sensors),
          # Properly convert POSIXct to Stata's %tc format (milliseconds since 01jan1960)
          timestamp = (as.numeric(as.POSIXct(time_value)) + 315619200) * 1000,
          .groups = "drop"
        )
    }
    
    # Rename the kelurahan field to match expected output
    kelurahan_summary <- kelurahan_summary %>%
      rename(KELURAHAN_NAME = kelurahan_name)
    
    return(kelurahan_summary)
  }, error = function(e) {
    cat("ERROR processing timestamp", format(time_value, "%Y-%m-%d %H:%M:%S"), ":", e$message, "\n")
    return(NULL)
  })
}

#===============================================================================
# IDENTIFY REPRESENTATIVE TIMESTAMPS FOR DISTANCE METRICS
#===============================================================================
# Calculate sensor availability for each timestamp
cat("\nIdentifying representative timestamps for distance calculations...\n")
timestamp_availability <- sensors_processed %>%
  group_by(rounded_datetime) %>%
  summarize(
    available_sensors = sum(!is.na(pm25)),
    .groups = "drop"
  ) %>%
  arrange(rounded_datetime)

# Find timestamps with max, min, and median sensor counts
max_sensors_timestamp <- timestamp_availability %>%
  arrange(desc(available_sensors)) %>%
  slice(1) %>%
  pull(rounded_datetime)

min_sensors_timestamp <- timestamp_availability %>%
  filter(available_sensors >= min_sensors_to_use) %>%  # Ensure we have enough sensors
  arrange(available_sensors) %>%
  slice(1) %>%
  pull(rounded_datetime)

# For median, get the middle value
median_index <- ceiling(nrow(timestamp_availability) / 2)
median_sensors_timestamp <- timestamp_availability %>%
  arrange(available_sensors) %>%
  slice(median_index) %>%
  pull(rounded_datetime)

# Store these timestamps in a list for easy checking
representative_timestamps <- c(max_sensors_timestamp, min_sensors_timestamp, median_sensors_timestamp)

cat("Selected representative timestamps for distance calculations:\n")
cat("- Maximum sensors (", 
    timestamp_availability$available_sensors[timestamp_availability$rounded_datetime == max_sensors_timestamp],
    " sensors): ", format(max_sensors_timestamp, "%Y-%m-%d %H:%M:%S"), "\n", sep="")
cat("- Minimum sensors (", 
    timestamp_availability$available_sensors[timestamp_availability$rounded_datetime == min_sensors_timestamp],
    " sensors): ", format(min_sensors_timestamp, "%Y-%m-%d %H:%M:%S"), "\n", sep="")
cat("- Median sensors (", 
    timestamp_availability$available_sensors[timestamp_availability$rounded_datetime == median_sensors_timestamp],
    " sensors): ", format(median_sensors_timestamp, "%Y-%m-%d %H:%M:%S"), "\n", sep="")

# Get list of all unique rounded timestamps
unique_times <- unique(sensors_processed$rounded_datetime)
cat("Total timestamps to process:", length(unique_times), "\n")

# Set up parallel processing
cat("Setting up parallel processing...\n")
cores <- detectCores() - 1  # Leave one core free for system processes
if(cores < 1) cores <- 1
cat("Using", cores, "CPU cores for parallel processing\n")
cl <- makeCluster(cores)
registerDoParallel(cl)

#===============================================================================
# RUN PARALLEL INTERPOLATION
#===============================================================================
# Apply IDW for each timestamp in parallel and combine results
cat("\nRunning parallel IDW interpolation...\n")
results <- foreach(i = seq_along(unique_times),
                   .packages = c("sf", "gstat", "dplyr", "geosphere"),
                   .export = c("perform_idw_for_timepoint", "min_sensors_to_use",
                               "nmax_points_to_use", "interpolation_grid",
                               "kelurahan_name_field", "representative_timestamps")) %dopar% {
                                 time_value <- unique_times[i]
                                 
                                 # Determine if we should calculate distances for this timestamp
                                 calculate_distances <- time_value %in% representative_timestamps
                                 
                                 # Call the IDW function with appropriate parameters
                                 result <- perform_idw_for_timepoint(
                                   sensor_points, 
                                   time_value,
                                   kelurahan,
                                   interpolation_grid,
                                   kelurahan_name_field = kelurahan_name_field,
                                   min_sensors = min_sensors_to_use,
                                   nmax_points = nmax_points_to_use,
                                   idp_power = 2,
                                   calculate_distances = calculate_distances,
                                   representative_timestamps = representative_timestamps
                                 )
                                 
                                 # Return the result
                                 result
                               }

# Stop the cluster
stopCluster(cl)
cat("\nParallel processing complete\n")

#===============================================================================
# PROCESS RESULTS
#===============================================================================
# Remove NULL results and combine into one dataframe
all_results <- results[!sapply(results, is.null)]
final_kelurahan_data <- bind_rows(all_results)

cat("\nIDW interpolation complete. Successfully processed", length(all_results), "out of", length(unique_times), "timestamps.\n")
cat("Success rate:", round(100 * length(all_results) / length(unique_times), 1), "%\n")

# Log timestamps that failed
if(length(all_results) < length(unique_times)) {
  failed_count <- length(unique_times) - length(all_results)
  cat("Failed to process", failed_count, "timestamps, likely due to insufficient sensor data.\n")
}

#===============================================================================
# SAVE RESULTS
#===============================================================================
# Define output filenames with date patterns
dta_output_file <- file.path(dirs$output, paste0("jakarta_kelurahan_pm25", date_suffix, ".dta"))

# Also create a special file for distance metrics
distance_output_file <- file.path(dirs$output, paste0("jakarta_kelurahan_distances", date_suffix, ".dta"))

# Filter results to separate regular data from distance metrics
distance_data <- final_kelurahan_data %>%
  filter(!is.null(timestamp_type) & timestamp_type != "regular") %>%
  select(KELURAHAN_NAME, timestamp_type, min_distance, median_distance, avg_distance, max_distance, 
         n_sensors_used, n_contributing_sensors, timestamp)

regular_data <- final_kelurahan_data %>%
  select(-timestamp_type)  # Remove timestamp_type column from regular data

temp_output_dir <- file.path(tempdir(), "jakarta_pm25")

# Create temp output directory if it doesn't exist
if (!dir.exists(temp_output_dir)) {
  dir.create(temp_output_dir, recursive = TRUE)
}

# Define temp output files
temp_dta_output_file <- file.path(temp_output_dir, paste0("jakarta_kelurahan_pm25", date_suffix, ".dta"))
temp_distance_output_file <- file.path(temp_output_dir, paste0("jakarta_kelurahan_distances", date_suffix, ".dta"))

# Save results to Stata format only
cat("\nSaving results to Stata format...\n")
# First try to save regular PM2.5 data to the original output directory
tryCatch({
  # Save to Stata format
  write_dta(regular_data, dta_output_file)
  cat("PM2.5 data saved successfully to:", dta_output_file, "\n")
  
  # Save distance metrics if we have any
  if(nrow(distance_data) > 0) {
    write_dta(distance_data, distance_output_file)
    cat("Distance metrics saved successfully to:", distance_output_file, "\n")
  }
}, error = function(e) {
  # If original save fails, save to temp directory
  cat("ERROR: Failed to save to original location:", e$message, "\n")
  cat("Attempting to save to temporary directory...\n")
  
  # Save to temp directory
  tryCatch({
    write_dta(regular_data, temp_dta_output_file)
    cat("PM2.5 data saved to temporary location:", temp_dta_output_file, "\n")
    
    if(nrow(distance_data) > 0) {
      write_dta(distance_data, temp_distance_output_file)
      cat("Distance metrics saved to temporary location:", temp_distance_output_file, "\n")
    }
  }, error = function(e2) {
    cat("ERROR: Failed to save to temporary location as well:", e2$message, "\n")
    cat("Results could not be saved to disk. Please free up space and run again.\n")
  })
})

#===============================================================================
# GENERATE SUMMARY REPORT
#===============================================================================
# Create a summary report
cat("\n=== Jakarta PM2.5 Interpolation Summary ===\n")
cat("Analysis run completed at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Performance optimizations used:\n")
cat("- Parallel processing with", cores, "CPU cores\n")
cat("- Increased grid cell size (0.005 degrees instead of 0.001)\n")
cat("- Reduced nmax points (10 nearest points)\n")
cat("- More efficient spatial joins\n")
cat("- Pre-computed interpolation grid\n")
cat("- Excluded sensors with invalid coordinates instead of assigning default locations\n")
cat("- Extended coordinate bounds to include Kepulauan Seribu (latitude range -7° to -5.4°)\n")
cat("- Improved handling of mixed frequency sensors\n")
cat("- Complete interpolation of all 30-minute timestamps\n")

if(nrow(final_kelurahan_data) > 0) {
  cat("\nResults summary:\n")
  cat("Total timestamps processed:", length(all_results), "\n")
  
  # Use min and max of timestamp values (now in double format)
  cat("Number of kelurahan:", n_distinct(final_kelurahan_data$KELURAHAN_NAME), "\n")
  cat("Overall average PM2.5:", round(mean(final_kelurahan_data$avg_pm25, na.rm = TRUE), 1), "μg/m³\n")
  
  # Print included fields
  cat("\nFields included in output data:\n")
  output_cols <- names(final_kelurahan_data)
  cat(paste(output_cols, collapse = ", "), "\n")
  
  # Report on n_contributing_sensors vs n_sensors_used and distance metrics
  cat("\nContributing sensors analysis:\n")
  sensor_stats <- final_kelurahan_data %>%
    summarize(
      avg_sensors_used = mean(n_sensors_used),
      avg_contributing_sensors = mean(n_contributing_sensors),
      avg_contribution_ratio = mean(n_contributing_sensors / n_sensors_used)
    )
  cat("Average sensors used per timestamp:", round(sensor_stats$avg_sensors_used, 1), "\n")
  cat("Average contributing sensors per kelurahan:", round(sensor_stats$avg_contributing_sensors, 1), "\n")
  cat("Average ratio of contributing to available sensors:", round(sensor_stats$avg_contribution_ratio*100, 1), "%\n")
  
  # Add distance metrics summary for representative timestamps
  cat("\nDistance metrics (in kilometers) for representative timestamps:\n")
  
  if(nrow(distance_data) > 0) {
    # Summarize by timestamp type
    distance_summary <- distance_data %>%
      group_by(timestamp_type) %>%
      summarize(
        avg_min_distance = mean(min_distance, na.rm = TRUE),
        avg_median_distance = mean(median_distance, na.rm = TRUE),
        avg_avg_distance = mean(avg_distance, na.rm = TRUE),
        avg_max_distance = mean(max_distance, na.rm = TRUE),
        sensor_count = first(n_sensors_used)
      )
    
    # Print summary for each timestamp type
    for(i in 1:nrow(distance_summary)) {
      ts_type <- distance_summary$timestamp_type[i]
      sensors <- distance_summary$sensor_count[i]
      
      cat("-- ", toupper(ts_type), " (", sensors, " sensors) --\n", sep="")
      cat("Average minimum distance:", round(distance_summary$avg_min_distance[i], 3), "km\n")
      cat("Average median distance:", round(distance_summary$avg_median_distance[i], 3), "km\n")
      cat("Average mean distance:", round(distance_summary$avg_avg_distance[i], 3), "km\n")
      cat("Average maximum distance:", round(distance_summary$avg_max_distance[i], 3), "km\n\n")
    }
  } else {
    cat("No distance metrics were calculated for representative timestamps.\n")
  }
  
  # Find top 5 kelurahan with highest average PM2.5
  top_kelurahan <- final_kelurahan_data %>%
    group_by(KELURAHAN_NAME) %>%
    summarize(avg_pm25 = mean(avg_pm25, na.rm = TRUE), .groups = "drop") %>%
    arrange(desc(avg_pm25)) %>%
    head(5)
  
  cat("\nKelurahan with highest average PM2.5:\n")
  print(top_kelurahan)
  
  cat("\nResults saved to:\n")
  cat(dta_output_file, "\n")
  cat("Temporary backup file (if main save failed):\n")
  cat(temp_dta_output_file, "\n")
} else {
  cat("No results were generated. Processing failed for all timestamps.\n")
  cat("Possible reasons:\n")
  cat("- Issues with IDW interpolation parameters\n")
  cat("- Insufficient number of sensors with valid data per timestamp\n")
  cat("- Problems with the input data format\n")
  cat("\nSuggested fixes:\n")
  cat("- Try different IDW parameters (nmax, idp_power)\n")
  cat("- Check the input data for valid PM2.5 measurements\n") 
  cat("- Verify coordinates are valid for all sensors\n")
}

# Stop logging and close the connection
cat("\nLogging complete at", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Log file saved to:", log_file, "\n")
sink(NULL)  # Close the log file connection
