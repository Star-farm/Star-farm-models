/**
 * ================================================================================================
 * Name: Plant growth models
 * Description:
 *   This model defines the different plant growth models used in the STARFARM simulation.
 *   It provides a global mechanism for initializing and managing crop growth models associated 
 *   with different agricultural practices. 
 *
 *   Two specific submodels are currently implemented:
 *     1. basicModel – A simple generic crop growth model based on climatic and water balance factors.
 *     2. CERES 
 * 
 *   The models are designed to be called by each crop agent to compute daily biomass increments 
 *   and determine key phenological dates (sowing, harvesting, etc.).
 * 
 * Author: Patrick Taillandier
 * Tags: crop growth, irrigation, rice, STARFARM
 *
 * ================================================================================================
 */


model STARFARM 

import "../Biological Entities/Cultivar.gaml"

import "Grow model.gaml"

import "../../Constants.gaml"
 
 
  


// ======================================================================
// LUA-MD model
// ======================================================================


species lua_mdModel parent: Growth_model {
	string id <- LUA_MD;
	
	

	action day_biomass_growth(Crop c) {
			if (not c.is_dead) {
	       	
		      
		        if ((the_weather.humidity > pest_humidity_limit) and (the_weather.t_mean > pest_temp_limit) and flip(pest_infection_prob)) { 
		        	/*if (c.concerned_plot = Plot[0]) {
		        		write current_date + " -> " + c.concerned_plot.pest_load;
		        	}*/
		        	c.concerned_plot.pest_load <- c.concerned_plot.pest_load + pest_daily_increment;
		        }  
		        
				float daily_heat <- (the_weather.t_mean - c.variety.t_base);
				 
				if(daily_heat<0){daily_heat<-0.0;} 
		        c.accumulated_heat <- c.accumulated_heat + daily_heat;
		        c.growth_stage <- c.accumulated_heat / c.thermal_units_total;
			    
			    float k_water <- (c.concerned_plot.water_level < awd_pumping_threshold) ? drought_growth_reduction_factor : 1.0;
		        
		        c.concerned_plot.local_salinity <- c.concerned_plot.my_cell.salinity_level;
		        float k_salt <- 1.0;
		        if ( c.concerned_plot.local_salinity > c.salt_threshold_val) { 
		        	k_salt <- 1.0 - (salinity_sensitivity_slope * (c.concerned_plot.local_salinity - c.salt_threshold_val));
		        	   
		        	if (k_salt < 0) { k_salt <- 0.0; c.is_dead <- true;c.biomass <- 0.0; }
		        }
		        
		       
		         float k_pest <- max(min_k_pest,1.0 - c.concerned_plot.pest_load); // Impact direct des pestes
		       	
		     	 
		    	// 3. FLOOD IMPACT (Progressive Mode / Decay)
				float k_flood <- 1.0;
	    
    			if (c.concerned_plot.water_level > flood_stress_threshold) {  
    			 // Phase 1: Growth stop (Asphyxia / Dormancy)
    			
		       	 k_flood <- 0.0; 
		        
		        // Phase 2: Rotting if duration exceeds genetic tolerance
		        if (c.concerned_plot.stress_days_flood_continuous > (c.variety.max_flood_tolerance_days * stress_days_flood_continuous_coeff)) {
		            //we reduce biomass
		            float reduction <- flood_biomass_decay_rate *  min(1.0,(c.concerned_plot.stress_days_flood_continuous/c.variety.max_flood_tolerance_days));
		            c.biomass <- c.biomass * (1.0 - ( flood_biomass_decay_rate * reduction));
		            // Safety check: If biomass becomes too small (< 50 g/m2), the plant actually dies
		            if (c.biomass < min_biomass_survival_threshold) { 
		               	c. is_dead <- true; 
		                c.biomass <- 0.0;
		                
		            } 
        		}
    		} 
    		float k_nitrogen <- compute_k_nitrogen(c);
			
			float fAPAR <- compute_fAPAR(c); 
    
    		
			// ----------------------------------------------------------------------
	        // NEW : DYNAMIC RUE (Diffuse Light Effect using cloud cover)
	        // ---------------------------------------------------------------------- 
	        float current_rue <- c.potential_rue_calibrated;
	        
	        // If the day is cloudy (e.g., autumn monsoon), light becomes diffuse.
	        // It penetrates the canopy better, increasing the overall plant efficiency.
	        if (the_weather.solar_rad < solar_rad_threshold)  {
	            // Calculate a factor from 0.0 to 1.0 based on how cloudy it is above the threshold
	             float diffuse_factor <- max(0.0, (solar_rad_threshold - the_weather.solar_rad) / solar_rad_threshold);
           		if (first_) {
	            	first_ <- false;
	            //	write string(current_date) + " -> " + sample(diffuse_factor) + " " + sample(the_weather.cloud_cover) + " " + sample(the_weather.solar_rad);
	            }
	            // Increase the RUE up to +25% on completely overcast days
	            current_rue <- current_rue * (1.0 + (diffuse_factor * max_diffuse_bonus));
	        }
  
       		float effective_solar_rad <- (max_light_limit * the_weather.solar_rad) / (steepness_factor + the_weather.solar_rad);
		
	      
    	    // 3. Calculation of raw daily growth with dynamic RUE
	        float daily_growth <- current_rue * effective_solar_rad * fAPAR * k_nitrogen * k_water * k_salt * k_pest * k_flood;

	   		c.biomass <- c.biomass + daily_growth;
	        
	       if (c.growth_stage > 0.75) {
                c.concerned_plot.sum_tmin_ripening <-  c.concerned_plot.sum_tmin_ripening + the_weather.t_min;
                 c.concerned_plot.sum_humidity_ripening <-  c.concerned_plot.sum_humidity_ripening + the_weather.humidity;
                 c.concerned_plot.sum_rain_ripening <-  c.concerned_plot.sum_rain_ripening + the_weather.rain;
                 c.concerned_plot.days_ripening <-  c.concerned_plot.days_ripening + 1;
            }
 

	       
            
	   		 if (c.concerned_plot.local_salinity > c.salt_threshold_val ) {
	        	c.cumulative_salt_stress_ripening <- c.cumulative_salt_stress_ripening + (c.concerned_plot.local_salinity - c.salt_threshold_val);
	    	}

	     
        }	
		
	}	
	
	bool first_ <- true update: true;
	
	float compute_k_nitrogen (Crop c) {
		float k_nitrogen <- 1.0;
    		if (c.growth_stage < n_late_stage_limit) {
	    		 // 1. Calculate the optimal requirement for the day
				float n_optimum_variety <- daily_n_consumption * (1.0 + (c.variety.nitrogen_response_eff * (n_saturation_threshold - 1.0)));
				
				float n_consumed <- 0.0;
				/*if c.concerned_plot = Plot(0) {
					write sample(n_optimum_variety) + " " + sample(c.nitrogen_stock) + " " + sample(c.growth_stage);
				}*/
				// 2. Dynamic Factor Calculation
				if (c.nitrogen_stock >= n_optimum_variety) {
				    /* * BOOST PHASE: High 'nitrogen_response_eff' acts as a yield accelerator.
				    * Realizes the "High-Yield Variety" (HYV) potential.
				    */
				    k_nitrogen <- 1.0 + (c.variety.nitrogen_response_eff * n_boost_max_factor);
				    n_consumed <- n_optimum_variety;
				
				} else if (c.nitrogen_stock > 0) {
				    /* * DEFICIT PHASE: High 'nitrogen_response_eff' acts as a vulnerability.
				    * The plant suffers more from the missing nitrogen.
				    */
				    float boost_ratio <- (c.nitrogen_stock - daily_n_consumption) / (n_optimum_variety - daily_n_consumption);
	    			k_nitrogen <- 1.0 + (c.variety.nitrogen_response_eff * n_boost_max_factor * boost_ratio);
					n_consumed <- c.nitrogen_stock;
				
				} else {
				    /* * DEPLETION PHASE: Growth is limited to the baseline rustic capacity.
				    */
				    k_nitrogen <- max(0.0, 1.0 - c.variety.nitrogen_response_eff);
				}
				c.nitrogen_stock <- max(0.0, c.nitrogen_stock - n_consumed);
			} 
			return k_nitrogen;
	}
	
	
 
	float compute_fAPAR (Crop c) {
		float fAPAR <- 0.0;
		  	// 1. Define the cumulative phenological thresholds for this cultivar
		    float emergence_threshold <- c.variety.tt_emergence;
		    float flowering_threshold <- emergence_threshold + c.variety.tt_veg;
		    float maturity_threshold  <- flowering_threshold + c.variety.tt_rep;
		    
		    // 2. Determine fAPAR based on the current accumulated thermal time
		    if (c.accumulated_heat < emergence_threshold) {
		        // Phase 1: Germination / Emergence (Very low canopy interception)
		        fAPAR <- fAPAR_phase1; 
		    } 
		    else if (c.accumulated_heat < flowering_threshold) {
		        // Phase 2: Vegetative growth (Leaf development and tillering)
		        fAPAR <- fAPAR_phase2; 
		    } 
		    else if (c.accumulated_heat < maturity_threshold) {
		        // Phase 3: Reproductive phase (Canopy closed, maximum light interception)
		        fAPAR <- fAPAR_phase3; 
		    } 
		    else {
		        // Phase 4: Grain filling / Senescence (Leaves are yellowing/drying)
		        fAPAR <- fAPAR_phase4; 
		    }
		    return fAPAR;
	}
}
 