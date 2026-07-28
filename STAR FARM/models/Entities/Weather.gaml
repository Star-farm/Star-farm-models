/**
* Name: Weather
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "../Global.gaml"



global {
	
	Weather the_weather;
	
	bool use_data <- false;
	
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
  	list<float> dry_solar_mean <- [208.2, 236.1, 252.4, 255.8, 226.4, 205.1, 192.3, 204.6, 184.2, 178.9, 183.5, 191.0];
	list<float> dry_solar_std  <- [34.78, 27.78, 23.66, 11.73, 16.25, 36.67, 55.84, 32.56, 30.52, 31.25, 52.29, 25.20];
	
	// Jours PLUVIEUX (Wet days) 
	list<float> wet_solar_mean <- [182.4, 210.2, 228.1, 225.4, 198.2, 189.5, 176.4, 181.2, 162.0, 160.5, 165.1, 171.4];
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
    
    
	list<list<date>> elNino_elNina <- [[date([2015,11]),date([2016,6])],[date([2019,11]),date([2020,6])]];
	
	// The peak salinity of a "normal" year today (e.g., 15.0 g/L at the coast)
	float initial_salt_peak <-6.5; 
	 
    // Base historique : Jours 60 à 120 (Mars-Avril)
    int salt_start_doy <- 60;
    int salt_end_doy   <- 120;
    
    float decay_duration <- 20.0;
    
    float climb_duration <- 30.0;
   
	 action init_weather_data() {
		if (the_weather = nil or not use_weather_generator) {
			create Weather {
				the_weather <- self; 
				do load_real_data();
				
			}
			
		}
	}
	
	// ==========================================
    // --- ENSO DYNAMICS (El Niño / La Niña)
    // ==========================================
    int enso_state <- 0; // -1 = La Niña, 0 = Neutral, 1 = El Niño
    
    // Default Probabilities (Historical Baseline)
    float prob_el_nino <- 0.25;
    float prob_la_nina <- 0.25;
    
    // Intensity Modifiers (Adjustable per scenario)
    float el_nino_rain_modifier <- 0.70; // -30% rainfall during El Nino
    float el_nino_temp_offset <- 1.0;    // +1.0°C during El Nino
  //  float el_nino_salinity_modifier <- 1.5; // +50% strength for saline intrusion
    
    float la_nina_rain_modifier <- 1.20; // +20% rainfall during La Nina
    float la_nina_temp_offset <- -0.5;   // -0.5°C during La Nina
    //float la_nina_salinity_modifier <- 0.8; // Salinity pushed back by high river flow
	
	bool is_elNino_elNina (date d) {
		loop el over: elNino_elNina {
			if (d between (el[0],el[1])) {
				return true;
			}
				
		}
		return false;
	}
		
	
	
	action generate_scenario(string scen_name, int start_year, int end_year, float temp_rise_total, float salt_max_intrusion, float rain_intensity_max, float typhoon_probability_max,  int salt_start_doy_coeff, int salt_end_doy_coeff,
		float prob_el_nino_target, float prob_la_nina_target, float el_nino_temp_offset_target, float el_nino_rain_modifier_target
	) {
        
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
        int enso_state_y <- 0;
        bool el_ni <- false;    
        loop year from: start_year to: end_year {
        	
           
            float progress <- (year - start_year) / (end_year - start_year);
            float prob_el_nino_ <- prob_el_nino + (prob_el_nino_target - prob_el_nino)*progress;
            float prob_la_nina_ <- prob_la_nina + (prob_la_nina_target - prob_la_nina)*progress;
            float el_nino_temp_offset_ <- el_nino_temp_offset + (el_nino_temp_offset_target - el_nino_temp_offset)*progress;
           // float el_nino_salinity_modifier_ <- el_nino_salinity_modifier + (el_nino_salinity_modifier_target - el_nino_salinity_modifier)*progress;
            float el_nino_rain_modifier_ <- el_nino_rain_modifier + (el_nino_rain_modifier_target - el_nino_rain_modifier) *progress;
            float current_warming <- temp_rise_total * progress;
           	
           	if (not el_ni) {
	           	float rnd_val <- rnd(1.0);
	            if (rnd_val < prob_el_nino_) {
	                enso_state_y <- 1;
	                elNino_elNina << [date([year,11]),date([year+1,6])];
	                el_ni <- true;
	            } else if (rnd_val < (prob_el_nino_ + prob_la_nina_)) {
	                enso_state_y <- -1;
	                elNino_elNina << [date([year,11]),date([year+1,6])];
	                el_ni <- true;
	            }
	         } else {
	         	el_ni <- false;
	         } 
	        
            // The total risk for the current year (Today + future aggravation)
			float current_salt_risk <- initial_salt_peak + (salt_max_intrusion * progress);

            
            float current_rain_intensity <- 1.0 + ((rain_intensity_max - 1.0) * progress);
            float current_typhoon_prob <- typhoon_probability_max * progress;
             
            loop doy from: 1 to: date([year]).days_in_year {
                
                date d <- date([year,1,1]) add_days (doy - 1);
                enso_state <-is_elNino_elNina(d) ? enso_state_y : 0;
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
             
                float salinity <- base_salinity + current_salt_risk * compute_salinity_factor(doy, (salt_start_doy - int(salt_start_doy_coeff * progress)) ,(salt_end_doy + int(salt_end_doy_coeff * progress)), enso_state =1 );
                
            
                if (enso_state = 1) { // El Niño Mode
			        rain_amount <- rain_amount * el_nino_rain_modifier_;
			        t_max <- t_max + el_nino_temp_offset_;
			        t_min <- t_min + el_nino_temp_offset_;
        
    			} else if (enso_state = -1) { // La Niña Mode
			        rain_amount <- rain_amount * la_nina_rain_modifier;
			        t_max <- t_max + la_nina_temp_offset;
			        t_min <- t_min + la_nina_temp_offset;
				}
                
                
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
    
   
	float compute_salinity_factor(int current_doy, int salt_start_doy_, int salt_end_doy_, bool is_el_nino) {
    	 if (is_el_nino) {
	    	int el_nino_start <- (salt_start_doy_ + 365) - 90; 
         	int el_nino_plateau_end <- salt_end_doy_; 
        	int el_nino_total_end <- salt_end_doy_ + 20; 

	    	
	    	if (current_doy >= el_nino_start or current_doy <= el_nino_total_end) { 
	            if (current_doy >= el_nino_start) {
	                return min(1.25, 0.55 + (0.7 * (current_doy - el_nino_start) / climb_duration)); 
	            } else if (current_doy <= el_nino_plateau_end) {
	                // Pic absolu et plateau de janvier à fin avril
	                return 1.25; 
	            } else if (current_doy > el_nino_plateau_end and current_doy <= el_nino_total_end) {
	                // Redescend et disparaît en mai grâce aux premières pluies
	                return max(0.0, 1.25 - ((current_doy - el_nino_plateau_end) / decay_duration)); 
	            }
	        }
		} else {
		    	// Rain flushes the salt out of the canals
			//if (rain_amount_ > 10.0) { return 0.0; }
		    if (current_doy >= salt_start_doy_ and current_doy <= salt_end_doy_) {
		     	// Le pic normal est plus court et moins violent
		        return 0.6 * sin(((current_doy - salt_start_doy_) / (salt_end_doy_/2)) * 180); 
		    }
		}
	   	return 0.0;
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
	map<date,float> _cloud_clover;
	
	float t_mean;  
	float t_max; 
	float t_min;
    float solar_rad; 
    float cloud_cover;
    float humidity; 
    float rain;
    float salinity <- 0.0;  
	
	 reflex update_weather {
	 	if not( current_date in _temp_min.keys) {
	 		if not (mode_batch) {
	 			ask world {
	 				do pause();
	 			} 
	 		} else {
	 			ask world {do compute_fitness();}
	 			end_of_sim <- true; 
	 		}
	 	} else {
	 		t_min <- _temp_min[current_date]; 
	 		cloud_cover <- _cloud_clover[current_date]; 
	 		t_max <- _temp_max[current_date];
		 	t_mean <- (t_min + t_max)/2; 
		 	solar_rad <- _solar_radiation[current_date] / 1000.0;
		 	humidity <-  _humidity[current_date]; 
		 	rain <- _rainfall[current_date]; 
		 	salinity <- empty(_salinity) ? 1.0 : _salinity[current_date];
	 	}
    }
     
    action load_real_data() {
    	use_data <- true;
    	csv_file f <- csv_file(weather_file, ";", true);
     	matrix mat <- matrix(f);
        
        loop i from: 1 to: mat.rows - 1 {
            list<string> date_str <- string(mat[1, i]) split_with "/";
            date d <- date([int(date_str[2]),int(date_str[1]),int(date_str[0])]);
            if (ending_date != nil and d > ending_date) {
            	continue;
            }
            _temp_max[d] <- float(mat[2, i]);
            _temp_min[d] <- float(mat[3, i]); 
            _humidity[d] <- float(mat[6, i]);
            _rainfall[d] <- float(mat[7, i]);      
            _windspeed[d] <- float(mat[8, i]);
            _cloud_clover[d] <- float(mat[11, i]);
            _solar_radiation[d] <- float(mat[13, i]) * 1000.0;  
          //  write "" + (d.year) + "/" + d.month +"/" + d.day+" -> " + (world.is_elNino(d, prob_el_nino,prob_la_nina) = 1);
	   
            float f_ <- world.compute_salinity_factor(d.day_of_year,salt_start_doy,salt_end_doy, world.is_elNino_elNina(d));
         	_salinity[d] <- base_salinity + initial_salt_peak * f_;              
           
        }
        
    }
	 
} 

