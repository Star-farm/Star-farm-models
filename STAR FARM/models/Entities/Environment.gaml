/**
* Name: Environment
* Author: Patrick Taillandier
* Tags: 
*/


model Environment

import "Plant growth models.gaml"

 
global {
	 float total_province_pumping <- 0.0;  
	 
	  
	 reflex environmental_dynamics {
    	total_province_pumping <- sum(Crop collect (each.water_pumped_today));
    	ask unit_cell {
    		
	    		// --- 1. GEOGRAPHIC FACTOR (Spatial) ---
	        // Mekong Delta: The South (large y) is closer to the sea, the North (small y) is protected.
	        // Factor ranges from 0.0 (North) to 1.0 (South)
	        float location_vulnerability <- grid_y / grid_resolution; 
	        
	          
	        // --- 2. BASE SALINITY (Climate Dynamics) ---
	        // We combine the daily threat (CSV) with the location vulnerability.
	        // Ex: If CSV says 4g/L.
	        // - In the South (factor 1.0) -> Base = 4.0 g/L
	        // - In the North (factor 0.1) -> Base = 0.4 g/L
	        float base_sal <- the_weather.salinity * location_vulnerability;
	
	        // --- 3. HUMAN IMPACT (Feedback Loop) --- 
	        // If everyone pumps, it creates a depression that "sucks" salty water from the river into canals.
	        // This is the anthropogenic amplifier.
	        float human_impact <- 0.0;
	        if (total_province_pumping > 0) {
	            // Adjust the coefficient so the impact is significant but realistic (e.g., +0.5 to +1.0 g/L max)
	            human_impact <- total_province_pumping * water_extraction_salt_impact;
	        }
	    	
	      // --- 4. FINAL CALCULATION & RAIN DILUTION ---
	        float potential_salinity <- base_sal + human_impact;
	       
	        
	       //if (self = unit_cell(location) and not empty(Crop)) { write sample(human_impact) + " " + sample(water_extraction_salt_impact);}
	        // Local rain (on the plot) washes away salt immediately
	        // Simple dilution formula
	       float dilution_factor <- (the_weather.rain > 0) ? (1.0 / (1.0 + (the_weather.rain * 0.1))) : 1.0;
	        	 
	        salinity_level <- potential_salinity * dilution_factor;
	    		
			pollution_level <- pollution_level * pollution_decay_rate;
    	}
      	 
      	ask unit_cell { 
      		if (pollution_level > 0) {
      			float to_share <- pollution_level * pollution_diffusion_prop;
      			float to_share_n <- to_share / length(neighbors);
      			ask neighbors {
      				self.pollution_level_tmp <- self.pollution_level_tmp + to_share_n;
      			}

      			pollution_level <- pollution_level - to_share;
      		}

      		if (salinity_level > 0) { 
      			float to_share <- salinity_level * salinity_diffusion_prop;
      			float to_share_n <- to_share / length(neighbors);
      			ask neighbors {
      				self.salinity_level_tmp <- self.salinity_level_tmp + to_share_n;
      			}

      			salinity_level <- salinity_level - to_share;
      		}

      	}

      	ask unit_cell {
      		pollution_level <- pollution_level + pollution_level_tmp;
      		pollution_level_tmp <- 0.0;
      		salinity_level <- salinity_level + salinity_level_tmp;
      		salinity_level_tmp <- 0.0;
      	} 
   	} 
}

grid unit_cell width: grid_resolution height: grid_resolution {
    float pollution_level <- 0.0;
    float salinity_level <- 0.0;
    float pollution_level_tmp <- 0.0;
    float salinity_level_tmp <- 0.0;
  
    rgb color <- #white update: rgb(255 - (pollution_level * 500), 255, 255 - (pollution_level * 500));
    
}  