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

import "../Parameters.gaml" 

import "../Constants.gaml"

import "Weather.gaml"

 
import "Farms and Plots.gaml"

  
 

// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================

global {

	//map containing the Plant Grow Model associated to a practice (id of the practice)
	map<string,Plant_growth_model> PG_models;

	
	//action that creates at the initialization of the simulation the different plant growth models
	action create_plant_growth_models {
		map<string,Plant_growth_model> models;
		loop s over: Plant_growth_model.subspecies { 
			create s returns: new_practices;
			Plant_growth_model ct <- Plant_growth_model(first(new_practices));
			models[ct.id] <- ct ;
		}
		loop pract over: plant_grow_models.keys {
			PG_models[pract] <- models[plant_grow_models[pract]];
		}
	}	
}




// ======================================================================
// GENERIC PLANT GROWTH MODEL SPECIES
// ======================================================================

species Plant_growth_model virtual: true{
	string id; // Unique identifier for the model
	
	// Virtual methods to be implemented in derived models
	action day_biomass_growth(Crop c) virtual: true;	

	
	action initialize;
	/*int compute_crop_duration(Crop c) {
		int start <- current_date.day_of_year;
		int index_start <- c.the_farmer.practice.sowing.implementation_days index_of start;
		int harvesting_date <-  c.the_farmer.practice.harvesting.implementation_days[index_start];
		if (harvesting_date < start) {
			harvesting_date <- harvesting_date + 365;
		}
		return harvesting_date - start; 
	}*/
	 
	
	
	float compute_Ra {
    // constants
    
    	float lat_deg <- CRS_transform(world.location, "4326").location.y;
    
		int doy <- current_date.day_of_year;
	    float PI <- 3.141592653589793;
	    float Gsc <- 0.0820; // MJ m-2 min-1, constante solaire
	
	    // convert latitude to radians
	    float lat_rad <- lat_deg * PI / 180.0;
	 
	    // inverse relative distance Earth-Sun
	    float dr <- 1.0 + 0.033 * cos(2.0 * PI / 365.0 * doy);
	
	    // solar declination (radians)
	    float delta <- 0.409 * sin(2.0 * PI / 365.0 * doy - 1.39);
	
	    // sunset hour angle (radians)
	    float tmp <- -tan(lat_rad) * tan(delta);
	    // clamp tmp to [-1,1] to avoid NaN from acos for extreme lat/doy combos
	    if (tmp < -1.0) { tmp <- -1.0; }
	    if (tmp >  1.0) { tmp <-  1.0; }
	    float ws <- acos(tmp);
	
	    // Ra in MJ m-2 day-1
	    return (24.0 * 60.0 / PI) * Gsc * dr * ( ws * sin(lat_rad) * sin(delta) + cos(lat_rad) * cos(delta) * sin(ws) );
	}
	
} 

// ======================================================================
// CERES CROP GROWTH MODEL
// ======================================================================

species ceresModel parent: Plant_growth_model {
	string id <- CERES;
	
   	 /**** PARAMETERS FOR CERES PLANT GROWTH MODEL *****/
    float Tbase <- 8.0;
    float Topt_ceres  <- 30.0; 
    float k     <- 0.6;     // extinction coefficient 
    float P1    <- 500.0;   // °C.day emergence → panicle initiation
    float P5    <- 500.0;   // °C.day grain filling
    float RUE   <- 3.0;     // g DM / MJ
    float latitude <- 10.0;
    
    // Grain
    float HI_max          <- 0.50;
    float grain_fill_rate <- 0.03; // fraction/jour


	
   
    // --- STATE VARIABLES 
    map<Plot,float> tt;        // thermal time
    map<Plot,int> stage;         // 0=veg, 1=repro, 2=grain fill, 3=mat
    float LAI <- 0.1;

    // --- STATE VARIABLES
    float soil_water_init <- 200.0; //mm
    map<Plot, float> water_stress;  // 0–1
    map<Crop, float> Zr;
    
    // TECHNICAL VARIABLES
    map<Plot, float> last_growth;
	
	// weather
	
	float Ra update:  compute_Ra();
	
	action initialize{
//		ask plot_species {soil_water <- 0.8 * self.theta_fc * my_cultivar.Zr_ini;}
		water_stress <- create_map(list<Plot>(plot_species), list_with(length(plot_species), 1.0)) ;
	}
	
	
	// compute the yield in kg based on grain biomass
	float yield_computation(Crop c){ 
		return c.grain_biomass * 10 * c.concerned_plot.surface_in_ha ; // g/m² * 10 * ha
	}
	
	// update phenology. Remark: all plots (and crops) share the same variables (temperature,
	// development stage, etc. This makes sense until data (weather...) is made spatially explicit.
	
	action root_growth(Crop c) {
		if (Zr[c] = nil){
			Zr[c] <- c.variety.Zr_ini;
		}else{
			Zr[c] <- min(c.variety.Zr_max, Zr[c] + 5.0); // 5 mm / jour
		}
	}
	
	 
	reflex phenology {
        float dTT <- max(0, the_weather.t_mean - Tbase);
        ask plot_species{
        	if (self.associated_crop = nil){
        		myself.tt[self] <- 0.0;
        		myself.stage[self] <- 0;
        	}else{
        		myself.tt[self] <- myself.tt[self] + dTT;
        		if (myself.stage[self] = 0 and myself.tt[self] >= myself.P1) { myself.stage[self] <- 1; }
		        if (myself.stage[self] = 1 and myself.tt[self] >= (myself.P1 + myself.P5)) { myself.stage[self] <- 2; }
		        if (myself.stage[self] = 2 and myself.tt[self] >= (myself.P1 + 2 * myself.P5)) { myself.stage[self] <- 3; }
        	}
        	
        }
    }
    
    // update soil water balance 
    // Water balance will be moved out of plant growth (precipitation, drainage)
    
    action soil_water_balance(Crop c)  {
    	Plot p <- c.concerned_plot;

		float inflow;
		
		// ETo (Hargreaves)
		float ETo <- 0.0023 * (the_weather.t_mean + 17.8) * sqrt(max(0.0, the_weather.t_max - the_weather.t_min)) * Ra;
		
		// --- Irrigation logic
		float FC_mm <- c.concerned_plot.theta_fc * Zr[c];
		float WP_mm <- c.concerned_plot.theta_wp * Zr[c];
		
		
		 if (c.the_farmer.practice.has_practice(AWD)) {
	    	AWD_Irrigating_practice awd <- AWD_Irrigating_practice(c.the_farmer.practice.get_practice(AWD));
	    	  if (p.soil_water < awd.AWD_threshold * FC_mm) {
	            inflow <- the_weather.rain + awd.irrigation_amount;
	        }
	    	
	    }else{
	       if (p.soil_water < FC_mm) {
	        	inflow <- the_weather.rain + (FC_mm - p.soil_water);
	        }
	    }
	    
	   
	    // --- Outflows
	    float transpiration <- ETo * water_stress[p];
	    float drainage <- max(0, p.soil_water + inflow - FC_mm);
	
	    // --- Update soil water
	    p.soil_water <- p.soil_water + inflow - transpiration - drainage;
	
	    p.soil_water <- max(WP_mm, min(p.soil_water, FC_mm));
	     
	    
	    // update water stress
	    if (p.soil_water <= WP_mm) { 
            water_stress[p] <- 0.0;
        }
        else if (p.soil_water < FC_mm) {
            water_stress[p] <- (p.soil_water - WP_mm) / (FC_mm - WP_mm);
        }
        else {
            water_stress[p] <- 1.0;
        }
    }
     
    float compute_stress(Crop c){
        float N_demand <- compute_N_demand(c);
        float N_uptake <- min(c.concerned_plot.N_avail, N_demand) * c.concerned_plot.N_uptake_eff;
        c.concerned_plot.N_avail <- c.concerned_plot.N_avail - N_uptake;
        c.plant_N <- c.plant_N + N_uptake;
        
        // compute azote stress
        float N_conc;
		float N_stress;
		
		if (c.B <= 1e-6) {
            N_stress <- 1.0;
        } else { 
            N_conc <- c.plant_N / c.B; // g/g
            if (N_conc <= c.variety.N_min_conc) {
                N_stress <- 0.0;
            } else {
                N_stress <- min(1.0,
                    (N_conc - c.variety.N_min_conc) / (c.variety.N_max_conc - c.variety.N_min_conc)
                );
            }
        }
        return N_stress;
    }
    
    
    // compute the azote demand
    float compute_N_demand(Crop c) {
        float N_opt_CERES <- c.B * c.variety.N_max_conc;
        float demand <- max(0, N_opt_CERES - c.plant_N);
        return demand; 
    }
	
	
	action day_biomass_growth(Crop c){
		do root_growth(c);
		do soil_water_balance(c);
		float N_stress <- compute_stress(c);

		if (stage[c.concerned_plot] < 3) {
            float IPAR <- Ra * (1 - exp(-k * LAI));
            float stress <- water_stress[c.concerned_plot];
            float dBiomass <- IPAR * RUE * stress;

            c.B <- c.B + dBiomass;

            LAI <- LAI + 0.01 * dBiomass;
            
            do grain_filling(c, dBiomass, stress);
        }
	}
		 
	
	
	// =========================================================
    // GRAIN FILLING (HI dynamique)
    // =========================================================
    action grain_filling(Crop c, float daily_growth, float stress) {

        if (stage[c.concerned_plot] >= 2 and stage[c.concerned_plot] < 3) {

            float dGrain_pot <- daily_growth * grain_fill_rate * stress;

            float HI_current <- c.grain_biomass / max(1e-6, c.B);

            if (HI_current < HI_max) {
                float dGrain <- min(
                    dGrain_pot,
                    HI_max * c.B - c.grain_biomass
                );
                c.grain_biomass <- c.grain_biomass + dGrain;
            }
        }
    }
}



// ======================================================================
// LUA-MD model
// ======================================================================


species lua_mdModel parent: Plant_growth_model {
	string id <- LUA_MD;
	
	

	action day_biomass_growth(Crop c) {
		if (not c.is_dead) {
       	
	        if (the_weather.humidity > pest_humidity_limit and the_weather.t_mean > pest_temp_limit and flip(pest_infection_prob)) { 
	        	c.concerned_plot.pest_load <- c.concerned_plot.pest_load + pest_daily_increment;
	        } 
	        
			float daily_heat <- (the_weather.t_mean - c.variety.t_base);
			
			if(daily_heat<0){daily_heat<-0.0;} 
	        c.accumulated_heat <- c.accumulated_heat + daily_heat;
	        c.growth_stage <- c.accumulated_heat / c.thermal_units_total;
		    float k_water <- (c.water_level < awd_pumping_threshold) ? drought_growth_reduction_factor : 1.0;
	        
	        c.concerned_plot.local_salinity <- c.concerned_plot.my_cell.salinity_level;
	        float k_salt <- 1.0;
	        if ( c.concerned_plot.local_salinity > c.salt_threshold_val) { k_salt <- 1.0 - (salinity_sensitivity_slope * max(0, c.concerned_plot.local_salinity - c.salt_threshold_val)); }
	        
	        if (k_salt < 0) { k_salt <- 0.0; c.is_dead <- true;c.biomass <- 0.0; }
	  
	        float k_pest <- max(0.2,1.0 - c.concerned_plot.pest_load); // Impact direct des pestes
	       	
	     	
	    	// 3. FLOOD IMPACT (Progressive Mode / Decay)
			float k_flood <- 1.0;
    
    		if (c.water_level > flood_stress_threshold) {  
		        // Phase 1: Growth stop (Asphyxia / Dormancy)
		        k_flood <- 0.0; 
		        
		        // Phase 2: Rotting if duration exceeds genetic tolerance
		        if (c.concerned_plot.stress_days_flood_continuous > c.variety.max_flood_tolerance_days) {
		            //we reduce biomass
		            c.biomass <- c.biomass * (1.0 - flood_biomass_decay_rate);
		            // Safety check: If biomass becomes too small (< 50 g/m2), the plant actually dies
		            if (c.biomass < min_biomass_survival_threshold) { 
		               	c. is_dead <- true; 
		                c.biomass <- 0.0;
		                
		            }
        		}
    		} 
    		 
    		 // 1. Calculate the optimal requirement for the day
			float n_optimum_variety <- daily_n_consumption * (1.0 + (c.variety.nitrogen_response_eff * (n_saturation_threshold - 1.0)));
			float k_nitrogen <- 1.0;
			
			// 2. Dynamic Factor Calculation
			if (c.nitrogen_stock >= n_optimum_variety) {
			    /* * BOOST PHASE: High 'nitrogen_response_eff' acts as a yield accelerator.
			    * Realizes the "High-Yield Variety" (HYV) potential.
			    */
			    k_nitrogen <- 1.0 + (c.variety.nitrogen_response_eff * n_boost_max_factor);
			
			} else if (c.nitrogen_stock > 0 and c.nitrogen_stock < daily_n_consumption) {
			    /* * DEFICIT PHASE: High 'nitrogen_response_eff' acts as a vulnerability.
			    * The plant suffers more from the missing nitrogen.
			    */
			    float boost_ratio <- (c.nitrogen_stock - daily_n_consumption) / (n_optimum_variety - daily_n_consumption);
    			k_nitrogen <- 1.0 + (c.variety.nitrogen_response_eff * n_boost_max_factor * boost_ratio);
			
			} else if (c.nitrogen_stock <= 0) {
			    /* * DEPLETION PHASE: Growth is limited to the baseline rustic capacity.
			    */
			    k_nitrogen <- max(0.0, 1.0 - c.variety.nitrogen_response_eff);
			}
				 	
	    		
	   		float daily_growth <- c.potential_rue_calibrated * the_weather.solar_rad * k_water * k_salt * k_pest * k_flood * k_nitrogen;
	   
	        c.biomass <- c.biomass + daily_growth;
	        
        }
		
	}	
}
 