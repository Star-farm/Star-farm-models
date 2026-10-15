/**
* Name: Farms and Plots 
* Description: Core model defining the relationships between farmers, farms, plots, and crops
* within the STARFARM simulation. It represents the decision-making process of farmers
* and the biological and management processes occurring at the plot and crop levels.
* 
* Author: Patrick Taillandier
*/

model STARFARM 

import "Grow Models/Grow model.gaml"
import "Biological Entities/Aqua Species.gaml"
import "Environment.gaml"
import "Practices.gaml"
import "../Parameters.gaml"  


global {
	bool new_season <- false;
}   

/**
 * SPECIES Farmer 
 * Represents an individual farmer managing one farm and making decisions about practices.
 */
species Farmer {
	bool is_active <- false;
	bool ended_year <- false;
	bool ended_season <- false;
	Farm my_farm;  // Reference to the farm owned by this farmer
	
	// The current agricultural practice followed by the farmer
	Agricultural_strategy practice <- custom_practices ? nil : practices[possible_practices.keys[rnd_choice(possible_practices.values)]];
 	int num_seasons;
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

	float accumulated_labor_hours <- 0.0;
    float mechanization_costs <- 0.0;

	float water_usage update: my_farm.plots sum_of (each.associated_crop = nil ? 0.0 : each.associated_crop.irrigation_total);
	
	list<Farmer> neighbors;  // List of neighboring farmers (for diffusion of innovations)
	 
	init {
	 	if practice = nil {
	 		create Custom_practices {
	 			myself.practice <- self;
	 		}
	 	}
	 	int rice_seasons <- (practice.sowing != nil) ? length(practice.sowing.implementation_days) : 0;
	 	int aqua_seasons <- (practice.aqua_stocking != nil) ? length(practice.aqua_stocking.implementation_days) : 0;
	 	num_seasons <- rice_seasons + aqua_seasons;
	}

	/**
	 * Action: define_neighbors
	 * Defines neighbors based on spatial proximity.
	 */
	action define_neighbors() {
		neighbors <- Farmer at_distance neighbor_distance;
	}
	 
	/**
	 * Action: decide_practice
	 * Determines which decision model to use for adopting new practices.
	 */
	action decide_practice() {
		switch innovation_diffusion_model {
			match NEIGHBORS {
				do innovation_diffusion_neighbors();
			}
		}
	}
	 
	/**
	 * Action: innovation_diffusion_neighbors
	 * Farmers observe their neighbors’ success (measured by money)
	 * and tend to adopt the practices of wealthier farmers in their neighborhood.
	 */
	action innovation_diffusion_neighbors() {
		map<string, float> practice_candidates;
		
		loop p over: possible_practices.keys {
			list<Farmer> p_farmers <- (neighbors + self) where (each.practice.id = p);
			if not empty(p_farmers) {
				practice_candidates[p] <- p_farmers mean_of (each.money);
			} 
		}
		if sum(practice_candidates.values) > 0.0 {
			practice <- practices[practice_candidates.keys[rnd_choice(practice_candidates.values)]];
		}
	}
	
	action add_income(float income) { 
		day_revenue <- day_revenue + income;
		money <- money + income;
		ask practice {
			do add_to_indicator('Profit', income);
			day_income <- day_income + income;
			total_balance <- total_balance + income;
			balance_per_ha <- balance_per_ha + income / practice_area;
		}
	}
	
	action add_expenses(float expenses, string category) {
		day_expenses <- day_expenses + expenses;
		money <- money - expenses;
		ask practice {
			do add_to_indicator('Profit', -expenses);
			do add_to_indicator('Expense: '+category, expenses);
			day_expenses <- day_expenses + expenses;
			total_balance <- total_balance - expenses;
			balance_per_ha <- balance_per_ha - expenses / practice_area; 
		} 
	}	

	reflex change_practices when: cycle > 0 and current_date.day_of_year = init_day_of_year {
		do decide_practice();
	} 

	aspect default {
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
 * Represents a unit of land where one crop or aquaculture species can be cultivated.
 */
species Plot { 
	bool is_active <- false;
	Farmer the_farmer;        // The farmer managing this plot
	Crop associated_crop;     // The crop or aquaculture batch currently growing on the plot
	float surface_in_ha;      // surface in ha
	Cultivar last_variety;
	Aqua_species last_aqua_variety;
	bool last_harvest_was_aqua <- false;
	bool has_shrimp_nutrient_bonus <- false;
	
	// Soil parameters
	float soil_water <- 200.0;
	float N_avail <- 6.0;
	float N_uptake_eff <- 0.8;
	float theta_fc <- 0.32;
	float theta_wp <- 0.15;
	float Zr <- 50.0;
	
	unit_cell my_cell <- unit_cell(location);
	float water_level <- 50.0 min: (awd_pumping_threshold * 1.5);
 	float final_yield_ton_ha;
   	float straw_yield_ton_ha <- 0.0;
   	float methane_emissions_kg_ha;
    
    // Climate Stress Counters (For Star Farm KPIs)
    int stress_days_salinity <- 0; 
    int stress_days_drought <- 0;
    int stress_days_flood <- 0;
    int stress_days_flood_continuous <- 0;
    int max_stress_days_flood_continuous <- 0;
   
    float total_water_pumped <- 0.0;
    float local_salinity;
    float total_fertilizer_applied <- 0.0;
  	float pesticide_threshold;
    int pesticide_count <- 0;
   	int days_since_last_spray; 
	
	bool date_sowing_ok <- false;
	bool date_aqua_stocking_ok <- false;
	
    float soil_health <- 1.0 min: min_soil_health max: max_soil_health;
    
    // PESTICIDES & PESTS
    float pest_load <- 0.0;
	date last_harvest_date;
	float leftover_straw <- 0.0;
	float leftover_straw_base <- 0.0;
	float daily_methane <- 0.0;
	
	float target_nitrogen;
	float trigger_threshold;
	float actual_sold_yield;
	
	// Variables for dynamic climate-driven Harvest Index and Economics
    float sum_tmin_ripening <- 0.0;
    float sum_humidity_ripening <- 0.0;
    float sum_rain_ripening <- 0.0;
    int days_ripening <- 0;
    
    bool is_high_humidity;
	
	/**
	 * Reflex: sowing (Rice / Plant Crops)
	 */
	reflex sowing when: the_farmer.practice.sowing != nil and the_farmer.practice.sowing.to_apply(self, current_date.day_of_year) {
		if (not new_season) {
		 	new_season <- true;
		 	ask Farmer { is_active <- false; }
		 	ask Plot { is_active <- false; }
		}
		the_farmer.is_active <- true;
		is_active <- true;
	
		ask the_farmer.practice.sowing {
			do effect_with_labor(myself);
		} 
	}

	/**
	 * Reflex: aqua_stocking (Shrimp / Fish Aquaculture)
	 */
	reflex aqua_stocking when: the_farmer.practice.aqua_stocking != nil and the_farmer.practice.aqua_stocking.to_apply(self, current_date.day_of_year) {
		if (not new_season) {
		 	new_season <- true;
		 	ask Farmer { is_active <- false; }
		 	ask Plot { is_active <- false; }
		}
		the_farmer.is_active <- true;
		is_active <- true;

		ask the_farmer.practice.aqua_stocking {
			do effect_with_labor(myself);
		}
	}
	
	reflex regulate_hydrology {
    	// 1. WATER INPUT (Rainfall)
    	water_level <- water_level + the_weather.rain;

	    // 2. CONSTANT LOSSES (Evapotranspiration)
	    water_level <- water_level - daily_water_loss_mm;

	    // 3. PROPORTIONAL LOSSES (Seepage & Percolation)
	    if (water_level > 0) {
	   	    float lateral_leakage <- water_level * lateral_leakage_coefficient;
	   	    water_level <- water_level - lateral_leakage;
	    }
	    
	    // 4. OVERFLOW & FAST DRAINAGE
	    // During aquaculture, pond bunds hold deeper water (up to 400mm) than standard rice bunds
	    float current_max_capacity <- (associated_crop != nil and associated_crop.is_aquaculture) ? max(max_water_capacity, associated_crop.aqua_variety.min_water_level + 100.0) : max_water_capacity;
	    if (water_level > current_max_capacity) {
            float water_excess <- water_level - current_max_capacity;
            water_level <- water_level - (water_excess * water_excess_coefficient);
        }
    }
	
	reflex compute_methane {
		leftover_straw <- leftover_straw * leftover_straw_decrease_coefficient; 
	    if (leftover_straw < 1.0) {
	    	leftover_straw <- 0.0;
	    }
	    // Freshwater methanogenesis is active when flooded with a rice crop
	    if (water_level > minimum_water_level_for_ch4 and associated_crop != nil and not associated_crop.is_aquaculture) {
	        float current_emission <- daily_ch4_base;
	        if (leftover_straw > 0.0) {
	            current_emission <- current_emission + (leftover_straw * ch4_straw_multiplier);
	        }
	       	daily_methane <- current_emission;
	       	methane_emissions_kg_ha <- methane_emissions_kg_ha + daily_methane;
	    } else {
	        daily_methane <- 0.0; 
	    }
	}
	
	/**
	 * Reflex: harvesting (Rice / Plant Crops)
	 */
	reflex harvesting when: the_farmer.practice.harvesting != nil and the_farmer.practice.harvesting.to_apply(self, current_date.day_of_year) {
		the_farmer.ended_seasons <- the_farmer.ended_seasons + 1;
		the_farmer.ended_season <- true;
		if (the_farmer.ended_seasons = the_farmer.num_seasons) {
			the_farmer.ended_seasons <- 0;
			the_farmer.ended_year <- true;
		}
		ask the_farmer.practice.harvesting {
			do effect_with_labor(myself);
		} 
		
		if not(date_sowing_ok) and not the_farmer.practice.harvesting.collect_straw and not self.next_sowing_clean_straw() {
			last_harvest_date <- current_date;
			leftover_straw_base <- associated_crop.biomass * biomass_to_leftover_coeff;
		} else { 
			last_harvest_date <- nil; 
			leftover_straw_base <- 0.0;
		}
		leftover_straw <- leftover_straw_base;
		ask associated_crop {
			do die(); 
		}
		associated_crop <- nil;
	} 

	/**
	 * Reflex: aqua_harvesting (Shrimp / Fish Aquaculture)
	 */
	reflex aqua_harvesting when: the_farmer.practice.aqua_harvesting != nil and the_farmer.practice.aqua_harvesting.to_apply(self, current_date.day_of_year) {
		the_farmer.ended_seasons <- the_farmer.ended_seasons + 1;
		the_farmer.ended_season <- true;
		if (the_farmer.ended_seasons = the_farmer.num_seasons) {
			the_farmer.ended_seasons <- 0;
			the_farmer.ended_year <- true;
		}
		ask the_farmer.practice.aqua_harvesting {
			do effect_with_labor(myself);
		}
		last_harvest_date <- nil;
		leftover_straw_base <- 0.0;
		leftover_straw <- 0.0;

		ask associated_crop {
			do die();
		}
		associated_crop <- nil;
	}
	
	bool next_sowing_clean_straw() {
		if (the_farmer.practice.aqua_stocking != nil) {
			return true; // Pond preparation for shrimp cleans out rice straw
		}
		int n <- current_date.day_of_year;
		list<int> ns <- the_farmer.practice.sowing.implementation_days.keys where (each > n);
		if empty(ns) {
			n <- min(the_farmer.practice.sowing.implementation_days.keys);
		} else {
			n <- min(ns);
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

	reflex daily_pest_dynamics when: associated_crop = nil or associated_crop.is_aquaculture {
	    pest_load <- pest_load * pest_daily_decrease_coeff; 
	}

	action update_soil_status(bool is_fallow) {
        if (is_fallow) {
            soil_health <- soil_health + regeneration_rate;
        } else {
            soil_health <- soil_health - degradation_rate;
        }
    }
	
	aspect default {
		// Visual representation: empty plots are white; active plots are colored by their current production type (Rice, Shrimp, or Fish)
		rgb plot_color <- #white;
		if (associated_crop != nil) {
			string current_prod_type <- associated_crop.is_aquaculture ? associated_crop.aqua_variety.type : PROD_RICE;
			plot_color <- (current_prod_type in production_type_colors.keys) ? production_type_colors[current_prod_type] : the_farmer.practice.color;
			
		
		}
		draw shape color: plot_color border: #black;
		draw triangle(500) color:  the_farmer.practice.color border: #black depth: 5.0;
		
	}
	
	
}


/**
 * SPECIES Crop
 * Represents an individual crop or aquaculture cohort growing on a plot.
 */
species Crop {
	Cultivar variety;                      // Used when cultivating crops (Rice)
    Aqua_species aqua_variety;             // Used when cultivating aquaculture (Shrimp/Fish)
    bool is_aquaculture <- false;          // Flag distinguishing aquaculture from plant crops
	Farmer the_farmer;                     // The farmer who owns the crop
	Plot concerned_plot;                   // The plot where the crop is located
	int lifespan <- 0 update: lifespan + 1;// Number of days since sowing/stocking
	int crop_duration;                     // Expected total duration of the cycle

	// Biophysical state variables
	string irrigation_mode <- NO_IRRIGATION;
	float B <- 0.0;
	float grain_biomass <- 0.0;
	float irrigation_total;
	int irrigation_events;
	
    float nitrogen_stock; 
    float biomass <- 0.0;     
    float growth_stage <- 0.0;  
    float accumulated_heat <- 0.0; 
    bool is_harvested <- false;
    bool is_dead <- false;
    int stress_count <- 0; 
    
    float emergence_threshold;
    float flowering_threshold;
    float maturity_threshold;
   
    // Computed variables
    float thermal_units_total;
    float potential_rue_calibrated;
    float salt_threshold_val;          
    float cumulative_salt_stress_ripening <- 0.0;
    float current_harvest_index;
    
    float straw_yield_ton_ha <- 0.0;
    float profit_margin <- 0.0;
    float water_pumped_today;
  	
    float profit_net;
    float revenue <- 0.0;
    
	float plant_N <- 0.0;
	float seed_density_kg_ha;       
	
    float sum_tmin_ripening <- 0.0;
	 
	reflex plantGrow {
		Growth_model g_model; 
		
		if (is_aquaculture) {
			g_model <- G_models[AQUA_SPECIES];	
		} else {
			g_model <- G_models[RICE];	
		}
		
		ask g_model {
			do day_biomass_growth(myself);
		}  
		if (not is_aquaculture) {
            concerned_plot.pest_load <- concerned_plot.pest_load + (concerned_plot.my_cell.pollution_level * pest_pollution_feedback);
        }
	}
	
	reflex track_stress_days when: !is_harvested and !is_dead and !is_aquaculture {
	    // 1. SALINITY STRESS: Applied if salinity exceeds the cultivar tolerance threshold
	    if (concerned_plot.my_cell.salinity_level > variety.salinity_tolerance) {
	        concerned_plot.stress_days_salinity <- concerned_plot.stress_days_salinity + 1;
	    }
	    
	    // 2. DROUGHT STRESS: applied when water depth falls below a critical threshold (e.g., −200 mm)
		if (concerned_plot.water_level < drought_stress_threshold) {
	        concerned_plot.stress_days_drought <- concerned_plot.stress_days_drought + 1;
	    }
	    
	    // 3. FLOODING STRESS (SUBMERGENCE): if the water level exceeds a critical threshold, non-floating rice starts to suffocate
	    if (concerned_plot.water_level > flood_stress_threshold) {
	        concerned_plot.stress_days_flood <- concerned_plot.stress_days_flood + 1;
	        concerned_plot.stress_days_flood_continuous <- concerned_plot.stress_days_flood_continuous + 1;
	        concerned_plot.max_stress_days_flood_continuous <- max(concerned_plot.stress_days_flood_continuous, concerned_plot.max_stress_days_flood_continuous);
	    } else {
	    	concerned_plot.stress_days_flood_continuous <- 0;
	    }
	}
}