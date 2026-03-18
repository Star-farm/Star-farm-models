/**
* Name: Weather
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "../Global.gaml"



global {
	
	Weather the_weather;
	
	  
	  // ==========================================
    // --- DONG THAP CLIMATE BASELINE (2018-2023)
    // ==========================================
    // Températures (°C)
    list<float> mean_temp_month <- [26.0, 26.7, 27.8, 28.7, 28.4, 27.8, 27.4, 27.4, 27.0, 27.1, 27.2, 26.4];
    list<float> max_temp_month  <- [30.4, 31.6, 33.0, 33.6, 33.1, 32.2, 31.4, 31.3, 31.0, 31.3, 31.1, 30.3];
    list<float> min_temp_month  <- [22.6, 22.8, 23.8, 25.2, 25.4, 24.9, 24.7, 24.7, 24.4, 24.5, 24.3, 23.3];

    // Chaîne de Markov (Probabilités de Pluie)
    list<float> prob_wet_given_wet <- [0.536, 0.412, 0.558, 0.827, 0.908, 0.911, 0.938, 0.922, 0.915, 0.922, 0.844, 0.627];
    list<float> prob_wet_given_dry <- [0.253, 0.187, 0.179, 0.500, 0.560, 0.800, 1.000, 0.786, 0.800, 0.684, 0.564, 0.291];
    list<float> rain_amount_per_wet_day <- [5.19, 2.82, 6.48, 5.79, 10.23, 11.45, 15.91, 13.35, 17.01, 12.28, 7.60, 5.43];


    // Radiation Solaire et autres
    // ========================================================================
    // DONG THAP: SOLAR RADIATION DISTRIBUTIONS (Mean and Standard Deviation)
    // ========================================================================
    // Jours SECS (Dry days)
    list<float> dry_solar_mean <- [215.19, 238.63, 258.14, 274.12, 258.53, 228.17, 216.89, 228.99, 216.22, 212.94, 194.92, 209.64];
    list<float> dry_solar_std  <- [34.78, 27.78, 23.66, 11.73, 16.25, 36.67, 55.84, 32.56, 30.52, 31.25, 52.29, 25.20];

    // Jours PLUVIEUX (Wet days)
    list<float> wet_solar_mean <- [190.18, 217.76, 236.70, 237.30, 214.41, 204.20, 192.09, 197.35, 173.58, 172.92, 176.43, 180.86];
    list<float> wet_solar_std  <- [42.13, 19.24, 22.92, 35.62, 43.14, 45.01, 47.57, 43.27, 45.71, 50.34, 48.09, 32.64];
    
    
    // ========================================================================
    // DONG THAP: HUMIDITY DISTRIBUTIONS (Mean and Standard Deviation in %)
    // ========================================================================
    // Jours SECS (Dry days)
    list<float> dry_humidity_mean <- [79.00, 77.25, 75.97, 76.21, 79.11, 86.36, 85.34, 87.29, 86.77, 83.24, 81.61, 80.15];
    list<float> dry_humidity_std  <- [4.96, 5.43, 3.52, 4.36, 5.18, 4.59, 2.62, 3.06, 5.35, 5.36, 4.31, 4.81];

    // Jours PLUVIEUX (Wet days)
    list<float> wet_humidity_mean <- [81.64, 81.12, 78.93, 81.63, 86.97, 88.13, 88.60, 88.88, 89.22, 88.96, 85.90, 83.66];
    list<float> wet_humidity_std  <- [6.33, 5.23, 5.34, 5.55, 5.12, 4.52, 5.17, 4.33, 4.91, 5.22, 5.29, 4.78];
   
    float base_wind <- 2.2;
    float base_salinity <- 0.1; 
   
    // Base historique : Jours 60 à 120 (Mars-Avril)
    int salt_start_doy <- 60;
    int salt_end_doy   <- 120;
    
   
	 action init_weather_data {
		if (the_weather = nil or not use_weather_generator) {
			create Weather {
				the_weather <- self; 
				do load_real_data;
				
			}
			
		}
	}
	
	
	
	action generate_scenario(string scen_name, int start_year, int end_year, float temp_rise_total, float salt_max_intrusion, float rain_intensity_max, float typhoon_probability_max,  int salt_start_doy_coeff, int salt_end_doy_coeff) {
        
        weather_id <- scen_name;
        create Weather  {
            the_weather <- self;
        } 
        
        // ========================================================================
        // --- MEMORY VARIABLES FOR WEATHER PERSISTENCE (AUTOREGRESSION) ---
        // Real weather doesn't jump randomly every day; it follows multi-day trends.
        // We use "offsets" that remember a percentage of yesterday's deviation.
        // ========================================================================
        bool was_wet_yesterday <- false; 
        float t_max_offset <- 0.0;
        float t_min_offset <- 0.0;
        float solar_offset <- 0.0;
        float wind_offset <- 0.0;
        float previous_humidity <- 75.0; // Starting baseline
        
        loop year from: start_year to: end_year {
            
            float progress <- (year - start_year) / (end_year - start_year);
            float current_warming <- temp_rise_total * progress;
            float current_salt_risk <- salt_max_intrusion * progress;
            float current_rain_intensity <- 1.0 + ((rain_intensity_max - 1.0) * progress);
            float current_typhoon_prob <- typhoon_probability_max * progress;
             
            loop doy from: 1 to: date([year]).days_in_year {
                
                date d <- date([year,1,1]) add_days (doy - 1);
                int m_idx <- d.month - 1; 
                bool is_wet_season <- (d.month >= 5 and d.month <= 11);
                
                // ----------------------------------------------------------------
                // 1. RAIN & FLOODS (Markov Chain dictates the overall daily mood)
                // ----------------------------------------------------------------
                float rain_amount <- 0.0;
                bool is_raining_today <- false;
                
                if (was_wet_yesterday) {
                    is_raining_today <- flip(prob_wet_given_wet[m_idx]);
                } else {
                    is_raining_today <- flip(prob_wet_given_dry[m_idx]);
                }
                
                if (is_raining_today) {
                    float mean_rain <- rain_amount_per_wet_day[m_idx];
                    rain_amount <- gauss(mean_rain, mean_rain * 0.5) * current_rain_intensity;
                }
                
                // Extreme typhoon events
                if (is_wet_season and flip(current_typhoon_prob)) { 
                    rain_amount <- 150.0 + rnd(50.0); 
                    is_raining_today <- true;
                }
                
                was_wet_yesterday <- is_raining_today; // Save for tomorrow
                
                // ----------------------------------------------------------------
                // 2. TEMPERATURE (Autoregressive smoothing)
                // offset = 70% of yesterday's offset + 30% new random noise
                // This creates natural "heat waves" or "cold spells" lasting several days.
                // ----------------------------------------------------------------
                t_min_offset <- (t_min_offset * 0.7) + gauss(0, 0.5);
                t_max_offset <- (t_max_offset * 0.7) + gauss(0, 0.6);
                
                float t_min <- min_temp_month[m_idx] + current_warming + t_min_offset;
                float t_max <- max_temp_month[m_idx] + current_warming + t_max_offset;
                
                // Physical constraint: Rain immediately cools down the maximum temperature
                if (is_raining_today) { 
                    t_max <- t_max - rnd(1.0, 3.0); 
                }
                
                // ----------------------------------------------------------------
                // 3. SOLAR RADIATION (Persistence of cloud coverage)
                // ----------------------------------------------------------------
               
               float daily_solar_mean <- 0.0;
                float daily_solar_std <- 0.0;
                
                // Select the proper distribution based on today's weather state
                if (is_raining_today) {
                    daily_solar_mean <- wet_solar_mean[m_idx];
                    daily_solar_std <- wet_solar_std[m_idx];
                } else {
                    daily_solar_mean <- dry_solar_mean[m_idx];
                    daily_solar_std <- dry_solar_std[m_idx];
                }
                
                // Draw a random base value from the Gaussian distribution
                float raw_solar <- (gauss(daily_solar_mean, daily_solar_std));
                 
                // Safety bound to prevent negative or impossibly low radiation 
                // on extreme random draws (especially during high variance wet months)
                raw_solar <- min(330.0,max(90.0,raw_solar));
                
                // Apply the calibration multiplier (88.0) to account for field 
                // efficiency / invisible yield losses without touching crop equations.
                float solar <- raw_solar * 85.0;
               
                // ----------------------------------------------------------------
                // 4. WIND (Smoothed)
                // ----------------------------------------------------------------
                wind_offset <- (wind_offset * 0.5) + gauss(0, 0.3);
                float wind <- base_wind + wind_offset;
                
                if (rain_amount > 50.0) { wind <- wind + rnd(5.0, 15.0); } // Typhoon gusts
                
                // ----------------------------------------------------------------
                // 5. HUMIDITY (Data-driven bimodal distribution)
                // ----------------------------------------------------------------
                float daily_humidity_mean <- 0.0;
                float daily_humidity_std <- 0.0;
                
                // Select the proper distribution based on today's weather state
                if (is_raining_today) {
                    daily_humidity_mean <- wet_humidity_mean[m_idx];
                    daily_humidity_std <- wet_humidity_std[m_idx];
                } else {
                    daily_humidity_mean <- dry_humidity_mean[m_idx];
                    daily_humidity_std <- dry_humidity_std[m_idx];
                }
                
                // Draw a random base value from the Gaussian distribution
                float humidity <- gauss(daily_humidity_mean, daily_humidity_std);
              
                // Physical bounds (Relative Humidity cannot exceed 100% or drop to desert levels)
                if (humidity > 100.0) { humidity <- 100.0; } 
                if (humidity < 60.0) { humidity <- 60.0; }
                
                // ----------------------------------------------------------------
                // 6. SALINITY
                // ----------------------------------------------------------------
                float salinity <- base_salinity;
                if (doy > (salt_start_doy - int(salt_start_doy_coeff * progress)) and doy < (salt_end_doy + int(salt_end_doy_coeff * progress))) {
                    float daily_salt <- abs(gauss(current_salt_risk, 0.5));
                    if (daily_salt > salinity) { salinity <- daily_salt; }
                }
                
                // Rain flushes the salt out of the canals
                if (rain_amount > 10.0) { salinity <- base_salinity; }
                
                // ----------------------------------------------------------------
                // 7. DATA FORMATTING & RECORDING
                // ----------------------------------------------------------------
                salinity <- salinity with_precision 2;
                rain_amount <- rain_amount with_precision 2;
                humidity <- humidity with_precision 2;
                if (rain_amount < 0) { rain_amount <- 0.0; }
                
                the_weather._solar_radiation[d] <- solar; 
                the_weather._temp_min[d] <- t_min; 
                the_weather._temp_max[d] <- t_max; 
                the_weather._windspeed[d] <- wind; 
                the_weather._salinity[d] <- salinity; 
                the_weather._rainfall[d] <- rain_amount; 
                the_weather._humidity[d] <- humidity; 
            }
        }
    }
	
}
species Weather {
	map<date,float> _temp_min;
	map<date,float> _temp_max;
	map<date,float> _solar_radiation;
	map<date,float> _humidity;
	map<date,float> _windspeed;
	map<date,float> _rainfall;
	map<date,float> _salinity;
	
	float t_mean;  
	float t_max; 
	float t_min;
    float solar_rad; 
    float humidity; 
    float rain;
    float salinity <- 0.0;  
	
	 reflex update_weather {
	 	if not( current_date in _temp_min.keys) {
	 		if not (mode_batch) {
	 			ask world {
	 				do pause;
	 			} 
	 		} else {
	 			ask world {do compute_fitness;}
	 			end_of_sim <- true; 
	 		}
	 	} else {
	 		t_min <- _temp_min[current_date]; 
	 		t_max <- _temp_max[current_date];
		 	t_mean <- (t_min + t_max)/2; 
		 	solar_rad <- _solar_radiation[current_date] / 1000.0;
		 	humidity <-  _humidity[current_date]; 
		 	rain <- _rainfall[current_date];
		 	salinity <- empty(_salinity) ? 1.0 : _salinity[current_date];
	 	}
    }
     
    action load_real_data {
    	csv_file f <- csv_file(weather_file, ";");
     	matrix mat <- matrix(f);
        
        loop i from: 1 to: mat.rows - 1 {
            list<string> date_str <- string(mat[1, i]) split_with "-";
           
            date d <- date([date_str[0],date_str[1],date_str[2]]);
            
            _temp_max[d] <- float(mat[2, i]);
            _temp_min[d] <- float(mat[3, i]);
            _humidity[d] <- float(mat[5, i]);
            _rainfall[d] <- float(mat[6, i]);      
            _windspeed[d] <- float(mat[7, i]);
            _solar_radiation[d] <- float(mat[10, i]) * 1000.0;  
            
            
            _salinity[d] <- default_salinity; 
        }
        
    }
	
} 

