/**
* Name: Farms and Plots 
* Description: Core model defining the relationships between farmers, farms, plots, and crops
* within the STARFARM simulation. It represents the decision-making process of farmers
* and the biological and management processes occurring at the plot and crop levels.
* 
* Author: Patrick Taillandier
*/

model STARFARM 

import "Environment.gaml"

// Import external modules containing crop growth models, farming practices, and parameters
import "Practices.gaml"
import "../Parameters.gaml"  


global {
	bool new_season <- false;
}   

/**
 * SPECIES Farmer 
 * Represents an individual farmer managing one farm and making decisions about practices.
 */
species Farmer  {
	bool is_active <- false;
	bool ended_year <- false;
	bool ended_season <- false;
	
	Farm my_farm;  // Reference to the farm owned by this farmer
	
	// The current agricultural practice followed by the farmer
	Crop_strategy practice <- practices[possible_practices.keys[rnd_choice(possible_practices.values)]];
 	int num_seasons <- length(practice.sowing.implementation_days);
	int ended_seasons <- 0;
	
	float money; // Economic capital of the farmer
	float day_revenue update: 0.0; 
	float day_expenses update: 0.0;
	
	
	float profit_margin <- 0.0;
    
    float yearly_profit;
    float profit_net;
    float total_costs;
    float revenue <- 0.0;
	float plot_area;
	// Compute total water usage as the sum of irrigation water applied to all crops

	float accumulated_labor_hours <- 0.0;
    float mechanization_costs <- 0.0;

	float water_usage update: my_farm.plots sum_of (each.associated_crop = nil ? 0.0 : each.associated_crop.irrigation_total);
	
	list<Farmer> neighbors;  // List of neighboring farmers (for diffusion of innovations)
	 
	/**
	 * Action: define_neighbors
	 * Defines neighbors based on spatial proximity (distance = 1.0 m).
	 * This allows social interactions and practice diffusion between farmers.
	 */
	action define_neighbors {
		neighbors <- Farmer at_distance neighbor_distance;
	}
	 
	/**
	 * Action: decide_practice
	 * Determines which decision model to use for adopting new practices.
	 * Currently, only the neighbor-based innovation diffusion model is implemented.
	 */
	action decide_practice {
		switch innovation_diffusion_model {
			match NEIGHBORS {
				do innovation_diffusion_neighbors;
			}
		}
	}
	 
	/**
	 * Action: innovation_diffusion_neighbors
	 * Farmers observe their neighbors’ success (measured by money)
	 * and tend to adopt the practices of wealthier farmers in their neighborhood.
	 */
	action innovation_diffusion_neighbors {
		map<string, float> practice_candidates;
		
		// Evaluate each possible practice based on the average income of neighbors using it
		loop p over: possible_practices.keys {
			list<Farmer> p_farmers <- (neighbors + self) where (each.practice.id = p);
			if not empty(p_farmers) {
				practice_candidates[p] <- p_farmers mean_of (each.money);
			} 
		}
		// If there are viable candidates, adopt one probabilistically
		if sum(practice_candidates.values) > 0.0 {
			practice <- practices[practice_candidates.keys[rnd_choice(practice_candidates.values)]];
		}
	}
	
	// add income to the farmer and to the practice global indicator
	action add_income(float income){ 
		day_revenue <- day_revenue + income;
		money <- money + income;
		ask practice {
			do add_to_indicator('Profit',income);
			day_income <- day_income + income;
			total_balance <- total_balance + income;
			balance_per_ha <- balance_per_ha + income / practice_area;
		}
	}
	
	// add expenses to the farmer and to the practice global indicator. 
	// add expenses to the corresponding category for detailed visualization
	action add_expenses(float expenses, string category){
		day_expenses <- day_expenses + expenses;
		money <- money - expenses;
		ask practice {
			do add_to_indicator('Profit',-expenses);
			do add_to_indicator('Expense: '+category, expenses);
			day_expenses <- day_expenses + expenses;
			total_balance <- total_balance - expenses;
			balance_per_ha <- balance_per_ha - expenses / practice_area; 
		} 
	}	
	/**
	 * Reflex: change_practices
	 * Each year (on the same calendar day as initialization), farmers reconsider their practice.
	 */

	reflex change_practices when:cycle > 0 and current_date.day_of_year = init_day_of_year {
		do decide_practice;
	} 


   
	aspect default {
		// Each farmer is drawn using an image colored by their current practice
		draw farmer_image size: {50, 50} color: practice.color;
	} 
}


/**
 * SPECIES Farm 
 * Represents a set of plots managed by a single farmer.
 */
species Farm { 
	list<Plot> plots;  // All plots belonging to the farm
}



/** 
 * SPECIES Plot
 * Represents a unit of land where one crop can be cultivated.
 */

species Plot { 
	bool is_active <- false;
	Farmer the_farmer;        // The farmer managing this plot
	Crop associated_crop;     // The crop currently growing on the plot (if any)
	float surface_in_ha;      // surface in ha
	
	// Soil parameters
	float soil_water <- 200.0; 	     // water level in mm
	float N_avail <- 6.0;    // Available nitrogen (g/m2) in the soil
							  // value: BASIC: 2.0, CERES: 60.0
	float N_uptake_eff <- 0.8;   // uptake efficiency
	float theta_fc <- 0.32; // m3/m3
	float theta_wp <- 0.15; // m3/m3
	float Zr <- 50.0; // mm (initial)
	
	unit_cell my_cell <-unit_cell(location) ;
	float water_level <- 50.0 min: (awd_pumping_threshold *1.5);
 	float final_yield_ton_ha;
   	float straw_yield_ton_ha <- 0.0;
   	float methane_emissions_kg_ha;
     // Climate Stress Counters (For Star Farm KPIs)
    int stress_days_salinity <- 0; 
    int stress_days_drought <- 0;
    int stress_days_flood <- 0;
    int stress_days_flood_continuous <- 0;
    int max_stress_days_flood_continuous <- 0;
   
    float total_water_pumped <- 0.0; // <--- COMPTEUR EAU (mm)
    float local_salinity;
    float total_fertilizer_applied <- 0.0; // fertilizer counter (kg)
  	float pesticide_threshold;
    int pesticide_count <- 0;        //SPRAY COUNTER
   	int days_since_last_spray; 
	
	bool date_sowing_ok <- false;
	
   // 1.0 = Perfect soil, 0.6 = Highly degraded soil
    float soil_health <- 1.0 min: min_soil_health max: 1.0;
    
    // PESTICIDES & PESTS
    float pest_load <- 0.0;          // 0.0 (not infected) à 1.0 (Infected)
	date last_harvest_date;
	float leftover_straw <- 0.0;
	float leftover_straw_base <- 0.0;
	float daily_methane <- 0.0;
	
	float target_nitrogen;
	float trigger_threshold;
	
	
	/**
	 * Reflex: sowing
	 * Checks whether sowing should occur according to the practice calendar
	 * and creates a new crop on the plot if conditions are met.
	 * Computes the expenses 
	 */
	reflex sowing when: the_farmer.practice.sowing.to_apply(self,current_date.day_of_year){
		 if (not new_season) {
		 	new_season <- true;
		 	ask Farmer {
		 		is_active <- false;
		 	}
		 	ask Plot {
		 		is_active <- false;
		 	}
		 }
		 the_farmer.is_active <- true;
		 is_active <- true;
	
		 ask the_farmer.practice.sowing {
			do effect_with_labor(myself);
		} 
		 
	}
	
	reflex regulate_hydrology {
    
    // 1. WATER INPUT (Rainfall + Potential Irrigation)
    // We add the rain from the weather agent to the current level
    	water_level <- water_level + the_weather.rain;

	    // 2. CONSTANT LOSSES (Evapotranspiration)
	    // ET is relatively constant as long as there is standing water
	    water_level <- water_level - daily_water_loss_mm;

	    // 3. PROPORTIONAL LOSSES (Seepage & Percolation)
	    // Darcy's Law: leakage through soil and bunds increases with water pressure (height)
	    // Here we simulate a 1.5% daily loss of the total water volume
	   if (water_level > 0) {
	   	 float lateral_leakage <- water_level * lateral_leakage_coefficient;
	   	 water_level <- water_level - lateral_leakage;
	   }
	   
	    
	    // 4. OVERFLOW & FAST DRAINAGE
	    // If water level exceeds the physical height of the bunds (overflow_limit)
	    if (water_level > max_water_capacity) {
	        
        // We simulate fast but non-instantaneous drainage
        // a part of the excess water is evacuated daily through drainage canals
        float water_excess <- water_level - max_water_capacity;
        water_level <- water_level - (water_excess * water_excess_coefficient);
    }
}
	
	
	reflex compute_methane  {
		leftover_straw <- leftover_straw * leftover_straw_decrease_coefficient; 
	    if (leftover_straw < 1.0) {
	    	leftover_straw <- 0.0;
	     }
	    // Methane is ONLY produced if the soil is flooded (anaerobic conditions)
	    if (water_level > minimum_water_level_for_ch4) {
	        // 1. Base emission 
	        float current_emission <- daily_ch4_base;
	        
	        // 2. The explosion due to fresh straw (leftover_straw)
	        if (leftover_straw > 0.0) {
	            current_emission <- current_emission + (leftover_straw * ch4_straw_multiplier);
	        }
	        
	       if (associated_crop != nil) {
	       		daily_methane <- current_emission;
	       	 	methane_emissions_kg_ha <- methane_emissions_kg_ha + daily_methane;
	       } 
	        
	    } else {
	        // If the field is dry (aerobic), methane emissions drop to zero
	        daily_methane <- 0.0; 
	    }
	}
	
	reflex harvesting when: the_farmer.practice.harvesting.to_apply(self,current_date.day_of_year){
		the_farmer.ended_seasons <- the_farmer.ended_seasons +1;
		the_farmer.ended_season <- true;
		if (the_farmer.ended_seasons = the_farmer.num_seasons) {
			the_farmer.ended_seasons <- 0;
			the_farmer.ended_year<- true;
			
		}
		ask the_farmer.practice.harvesting {
			do effect_with_labor(myself);
		} 
		
		if not(date_sowing_ok) and not the_farmer.practice.harvesting.collect_straw and not self.next_sowing_clean_straw(){
			last_harvest_date <- current_date;
			leftover_straw_base <-  associated_crop.biomass * biomass_to_leftover_coeff;
			
		} else { 
			last_harvest_date <- nil; 
			leftover_straw_base <- 0.0;
		}
		leftover_straw <- leftover_straw_base;
		ask associated_crop {
			do die; 
		}
		
		associated_crop <- nil;
	} 
	
	bool next_sowing_clean_straw {
		int n <- current_date.day_of_year;
		list<int> ns <- the_farmer.practice.sowing.implementation_days.keys where (each > n);
		if empty(ns) {
			n <- min(the_farmer.practice.sowing.implementation_days.keys);
		}  else {
			n <- min (ns);
		}
		return the_farmer.practice.sowing.implementation_days[n];
	}	
	
	reflex apply_practices {
		ask the_farmer.practice.other_practices {
			if (to_apply(myself, current_date.day_of_year)) {
			 	do effect_with_labor(myself);
	 		} 
		}
	}

	reflex daily_pest_dynamics when: associated_crop = nil  {
	    pest_load <- pest_load * pest_daily_decrease_coeff; 
	    
	}

	action update_soil_status(bool is_fallow) {
        if (is_fallow) {
            // Regeneration (Scenario 1M_HA: Fallow period)
            soil_health <- soil_health + regeneration_rate;
          
        } else {
            // Degradation (Scenario BAU: Continuous cropping)
            // Logic: Soil degrades slightly after every intensive crop
            soil_health <- soil_health - degradation_rate;
        }
    }
	
	aspect default {
		// Visual representation: empty plots are white; cultivated plots take the color of the practice
		draw shape color: associated_crop = nil ? #white : the_farmer.practice.color border: #black;
	}
}


/**
 * SPECIES Crop
 * Represents an individual crop growing on a plot.
 */
species Crop  {
	Cultivar variety;
	Farmer the_farmer;     // The farmer who owns the crop
	Plot concerned_plot;   // The plot where the crop is located
	int lifespan <- 0 update: lifespan + 1;  // Number of days since sowing
	int crop_duration;     // Expected total duration of the crop cycle


	// Biophysical state variables
	string irrigation_mode <- NO_IRRIGATION;
	float B <- 0.0;          // Biomass (g per m2 to be consistent with CERES model)
	float grain_biomass <- 0.0;  // g/m²
	float irrigation_total;  // Cumulative irrigation (mm)
	int irrigation_events;   // Number of irrigation events
	
	
    float nitrogen_stock; 
    float biomass <- 0.0;     
    float growth_stage <- 0.0;  
    float accumulated_heat <- 0.0; 
    bool is_harvested <- false;
    bool is_dead <- false;
    int stress_count <- 0; 
    
    float emergence_threshold ;
    float flowering_threshold ;
    float maturity_threshold  ;
   
    
       // computed variables
    float thermal_units_total;         // number of total cycle required
    float potential_rue_calibrated;    // RUE 
    float salt_threshold_val;          
    
   
    float current_harvest_index;       // HI that decrease with stress
    
    float straw_yield_ton_ha <- 0.0;
    float profit_margin <- 0.0;
    float water_pumped_today;
  	
    float profit_net;
    float revenue <- 0.0;
    
   	
	// Azote 
	float plant_N <- 0.0;	 // g N/m²
	
	float seed_density_kg_ha;       
	
	
	reflex plantGrow  {
		ask  PG_models[the_farmer.practice.id] {
			do day_biomass_growth(myself);
		}  
		concerned_plot.pest_load <- concerned_plot.pest_load + (concerned_plot.my_cell.pollution_level * pest_pollution_feedback);
  
	}
	
	
	reflex track_stress_days when: !is_harvested and !is_dead {
    
	    // 1. SALINITY STRESS: Applied if salinity exceeds the cultivar tolerance threshold
	    if (concerned_plot.my_cell.salinity_level > variety.salinity_tolerance) {
	        concerned_plot.stress_days_salinity <- concerned_plot.stress_days_salinity + 1;
	    }
	    
	    // 2. DROUGHT STRESS: applied when water depth falls below a critical threshold (e.g., −200 mm)
		if (concerned_plot.water_level < drought_stress_threshold) {
	        concerned_plot.stress_days_drought <- concerned_plot.stress_days_drought + 1;
	    }
	    
	     // 3. FLOODING STRESS (SUBMERGENCE): if the water level exceeds a critical threshold, non-floating rice starts to suffocate {
	    if (concerned_plot.water_level> flood_stress_threshold) {
	        concerned_plot.stress_days_flood <- concerned_plot.stress_days_flood + 1;
	        concerned_plot.stress_days_flood_continuous <- concerned_plot.stress_days_flood_continuous + 1;
	        concerned_plot.max_stress_days_flood_continuous <- max( concerned_plot.stress_days_flood_continuous,concerned_plot.max_stress_days_flood_continuous );
	    } else {
	    	 concerned_plot.stress_days_flood_continuous <-  0;
	    }
	}
	
	
	  
}

