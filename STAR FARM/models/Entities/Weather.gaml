/**
* Name: Weather
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "../Global.gaml"



global {
	
	Weather the_weather;
	
	action init_weather_data {
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

