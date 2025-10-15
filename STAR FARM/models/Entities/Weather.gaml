/**
* Name: Weather
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "../Parameters.gaml"


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
					temp_min[d] <- float(mat[4,i]); 
					temp_max[d] <- float(mat[5,i]); 
					solar_radiation[d] <- float(mat[3,i]); 
					if (solar_radiation[d] = 0.0) {
						if (i > 0) {
							solar_radiation[d] <- last(solar_radiation.values);
						}
					}
					humidity[d] <- float(mat[6,i]); 
					windspeed[d] <- float(mat[7,i]); 
					rainfall[d] <- float(mat[8,i]); 
					
				}
			}
		}
	}
}
species Weather {
	map<date,float> temp_min;
	map<date,float> temp_max;
	map<date,float> solar_radiation;
	map<date,float> humidity;
	map<date,float> windspeed;
	map<date,float> rainfall;
	
}

