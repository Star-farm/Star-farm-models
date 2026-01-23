/**
* Name: Weather
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "../Global.gaml"



global {
	
	Weather the_weather;
	
	  
    // Baseline parameters for Dong Thap (averages)
    float base_solar_dry <- 18000.0;
    float base_solar_wet <- 13000.0;
    float base_t_min <- 24.0;
    float base_t_max <- 31.0;
    float base_wind <- 2.2;
    float base_salinity <- 0.1; // Eau douce par défaut
   
    // Base historique : Jours 60 à 120 (Mars-Avril)
     int salt_start_doy <- 60;
     int salt_end_doy   <- 120;
	
	 action init_weather_data {
		if (the_weather = nil or not use_weather_generator) {
			create Weather {
				the_weather <- self; 
				
				loop f over: folder(weather_folder) {
					matrix mat <- matrix( csv_file(weather_folder +"/"+ f, false));
					loop i from: 0 to: mat.rows-1 {
						date d <- date([int(mat[1,i]),1,1]);
						d <- d add_days (int(mat[2,i]) -1);
						_solar_radiation[d] <- float(mat[3,i]); 
						if (_solar_radiation[d] = 0.0) {
							if (i > 0) {
								_solar_radiation[d] <- last(_solar_radiation.values);
							}
						}
						_temp_min[d] <- float(mat[4,i]); 
						_temp_max[d] <- float(mat[5,i]); 
						_windspeed[d] <- float(mat[6,i]); 
						_salinity[d] <- float(mat[7,i]); 
						_rainfall[d] <- float(mat[8,i]); 
						_humidity[d] <- float(mat[9,i]); 
						
					
					}
				}
			}
			
		}
	}
	
	 action generate_scenario(string scen_name, int start_year, int end_year, float temp_rise_total, float salt_max_intrusion, float rain_intensity_max, float typhoon_probability_max,  int salt_start_doy_coeff, int salt_end_doy_coeff) {
        
        weather_id <- scen_name;
        create Weather  {
        	the_weather <- self;
        }
        loop year from: start_year to: end_year {
            
            float progress <- (year - start_year) / (end_year - start_year);
            float current_warming <- temp_rise_total * progress;
            float current_salt_risk <- salt_max_intrusion * progress;
            float current_rain_intensity <- 1.0 + ((rain_intensity_max - 1.0) * progress);
            float current_typhoon_prob <- typhoon_probability_max * progress;

            string filename <- output_folder + scen_name + "/dongthap_" + year + "_" + scen_name + ".csv";
           	 
            loop doy from: 1 to: date([year]).days_in_year {
            	  bool is_wet_season <- (doy > 120) and (doy < 330);
                
                // 1. TEMPERATURE
                float seasonal_temp <- -1.5 * cos(360 * doy / 365);
                float t_min <- base_t_min + seasonal_temp + current_warming + gauss(0, 0.8);
                float t_max <- base_t_max + seasonal_temp + current_warming + 5.0 + gauss(0, 1.0);
                
                // 2. RAIN & FLOODS
                float rain_amount <- 0.0;
                if (is_wet_season) {
                    if (flip(0.65)) { rain_amount <- abs(gauss(15.0, 10.0)) * current_rain_intensity; }
                    if (flip(current_typhoon_prob)) { rain_amount <- 100.0 + rnd(80.0); }
                } else {
                    if (flip(0.05 * (1.0 - (0.5 * progress)))) { rain_amount <- abs(gauss(5.0, 2.0)); }
                }
                
                // 3. SALINITY
                float salinity <- base_salinity;
                if (doy > (salt_start_doy - int(salt_start_doy_coeff * progress)) and doy < (salt_end_doy + int(salt_end_doy_coeff * progress))) {
                    float daily_salt <- abs(gauss(current_salt_risk, 0.5));
                    if (daily_salt > salinity) { salinity <- daily_salt; }
                    
                }
                if (rain_amount > 10.0) { salinity <- base_salinity; }
                
                // 4. OTHER (Solar, Wind)
                float solar <- is_wet_season ? 13000.0 : 18000.0;
                if (rain_amount > 5.0) { solar <- solar * 0.5; } 
                solar <- solar + gauss(0, 2000);
                float wind <- 2.2 + gauss(0, 0.5);
                
                // 5. HUMIDITY 
                // Baseline: 75% in dry conditions, 85% in wet conditions.
                float humidity <- is_wet_season ? 85.0 : 75.0;
                
                // If it rains, it increases to 90–99%
                if (rain_amount > 0) {
                    humidity <- 90.0 + rnd(9.0); 
                } else {
                    // If it is very hot (high t_max), humidity decreases (dry air).
                    if (t_max > 33.0) { humidity <- humidity - 10.0; }
                    humidity <- humidity + gauss(0, 5.0);
                }
                
                // Physical bounds (40% to 100%)
                if (humidity > 100.0) { humidity <- 100.0; }
                if (humidity < 40.0) { humidity <- 40.0; }

               
                salinity <- salinity with_precision 2;
                rain_amount <- rain_amount with_precision 2;
                humidity <- humidity with_precision 2;
                if (rain_amount < 0) { rain_amount <- 0.0; }
                date d <- date([year,1,1]);
				d <- d add_days (doy -1);
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
	 			end_of_sim <- true; 
	 		}
	 	} else {
	 		t_min <-	_temp_min[current_date]; 
		 	t_max <- _temp_max[current_date];
		 	t_mean <- (t_min + t_max)/2; 
		 	solar_rad <- _solar_radiation[current_date] / 1000.0;
		 	humidity <-  _humidity[current_date]; 
		 	rain <- _rainfall[current_date];
		 	salinity <- empty(_salinity) ? 1.0 : _salinity[current_date];
	 	}
	 	
	 
    }
	
} 

