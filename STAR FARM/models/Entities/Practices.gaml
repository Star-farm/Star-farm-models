/**
 * ================================================================================================
 * Name: STARFARM
 * Description:
 *   This model defines the agricultural and aquaculture practices used in the STARFARM simulation
 *   framework. Rice practices and Aquaculture practices are strictly decoupled so that rotational
 *   systems (e.g., Rice-Shrimp) simply combine standard rice practices with aquaculture-specific
 *   practices.
 *
 * Based on: the internal empty template
 * Author: Patrick Taillandier
 * Tags: crop management, aquaculture, practices, rice, shrimp, STARFARM
 * ================================================================================================
 */

model STARFARM

import "Market.gaml"
import "../Global.gaml" 
import "../Constants.gaml" 

// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================

global {
	// Map storing all crop practices available in the model, keyed by their ID
	map<string,Agricultural_strategy> practices;
	
	// List of the indicators to be monitored
	list<string> key_indicators <- ["Harvest","Profit","Crop area","Water consumption","Fertilizer consumption","Current year","Current season"];
	// List of the expense categories, and the corresponding color for display
	map<string,rgb> expense_categories <- ["Seed"::rgb(22, 160, 133),"Fertilizer"::rgb(241, 196, 15),"Irrigation"::rgb(52, 152, 219),"Manpower"::rgb(230, 126, 34),"Other"::rgb(127, 140, 141)];
	int season_spring_3s <- 320;
	int season_autumn_3s <- 95;
	int season_winter_3s <- 215;
	int season_spring_2s <- 305;
	int season_autumn_2s <- 115;
	list<float> fert_trigger_thresholds_coeff_3_seasons <- [0.9, 1.0, 1.2];
	list<float> fert_targets_coeff_3_seasons <- [1.3, 1.3, 0.8];
	list<float> fert_trigger_thresholds_coeff_2_seasons <- [0.8, 1.0];
	list<float> fert_targets_coeff_2_seasons <- [1.2, 1.0];

	list<float> pesticide_thresholds_2_seasons <- [0.4, 1.0];		
	list<float> pesticide_thresholds_3_seasons <- [0.4, 0.6, 1.6];		
	int fallow_day <- 290;
	
	map<int, bool> three_seasons_sowing;
	map<int, bool> two_seasons_sowing;
	
	// Action to create all practice instances from their species definitions
	action create_practices() {
		three_seasons_sowing <- [int(season_spring_3s)::true, int(season_autumn_3s)::false, int(season_winter_3s)::false];
		two_seasons_sowing <- [season_spring_2s::true, season_autumn_2s::false];
	
		loop s over: Agricultural_strategy.subspecies { 
			create s returns: new_practices;
			Agricultural_strategy ct <- Agricultural_strategy(first(new_practices));
			practices[ct.id] <- ct;
		}
		ask Agricultural_strategy {
			do initialize();
		} 
	}
	
	// --- RICE PRACTICE BUILDERS ---
	Sowing_practice create_sowing_practice(Cultivar cultivar, map<int,bool> days_cleaning, bool mechanical) {
		create Sowing_practice (type_of_cultivar: cultivar, implementation_days: days_cleaning, mechanical_seeding: mechanical) returns: sow_pract;
		return first(sow_pract);
	}
	
	Harvesting_practice create_harvesting_practice(bool collect_straw) {
		create Harvesting_practice (collect_straw: collect_straw) returns: har_pract;
		return first(har_pract);
	}	
	 
	action add_AWD_practice(Agricultural_strategy pract) {
		create AWD_Irrigating_practice {
			pract.irrigation <- self;
			pract.other_practices << self;
		}
	}
	
	action add_fallow_practice(Agricultural_strategy pract, int doy_end) {
		create Fallow_practice {
			day_end_fallow <- doy_end;
			pract.other_practices << self;	
		} 
	}
	
	action add_CF_practice(Agricultural_strategy pract) {
		create CF_Irrigating_practice {
			pract.irrigation <- self;
			pract.other_practices << self;
		} 
	}
	
	action add_input_use_practice(Agricultural_strategy cp, map<int,float> trigger_thresholds_, float base_dose_, map<int,float> targets, bool mech) {
	    create Input_use_practice {
	        self.trigger_thresholds <- trigger_thresholds_;
	        self.base_dose <- base_dose_;
	        self.target_nitrogens <- targets;
	        self.mechanical <- mech;
	        cp.other_practices <- cp.other_practices + self;
	    }
	}
	
	action add_pesticide_practice(Agricultural_strategy pract, map<int,float> pesticide_thresholds, bool mec, bool IPM) {
		create Pesticide_application_practice (pesticide_thresholds: pesticide_thresholds, mechanical: mec) {
			pract.other_practices << self;
			ask pract.sowing {
				labor <- labor + (IPM ? labor_IMP_pest_management_hours : labor_pest_management_hours);
			}
		} 
	}

	// --- AQUACULTURE PRACTICE BUILDERS ---
	Aqua_Stocking_practice create_aqua_stocking_practice(Aqua_species sp, map<int,bool> stocking_days) {
		create Aqua_Stocking_practice (target_aqua_species: sp, implementation_days: stocking_days) returns: stock_pract;
		return first(stock_pract);
	}

	Aqua_Harvesting_practice create_aqua_harvesting_practice() {
		create Aqua_Harvesting_practice returns: a_harv_pract;
		return first(a_harv_pract);
	}

	action add_aqua_irrigating_practice(Agricultural_strategy pract) {
		create Aqua_Irrigating_practice {
			pract.other_practices << self;
		}
	}

	action add_aqua_feeding_practice(Agricultural_strategy pract, float feed_trigger, float feed_dose, float max_seasonal_feed) {
		create Aqua_Feeding_practice (
			trigger_threshold: feed_trigger,
			base_dose: feed_dose,
			target_feed: max_seasonal_feed
		) {
			pract.other_practices << self;
		}
	}
}


// ======================================================================
// BASE VIRTUAL PRACTICE
// ======================================================================

species Practice virtual: true {
	float labor;
	bool to_apply(Plot plot, int current_day) {
		return true;
	}
	
	action add_labor(Plot plot) {
		plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor;
	}
	
	action effect_with_labor(Plot plot) {
		do effect(plot);
		do add_labor(plot);
	}
	 
	action effect(Plot plot) virtual: true; 
} 


// ======================================================================
// RICE PRACTICES (Strictly applied to Plant / Rice Crops)
// ======================================================================

species Fallow_practice parent: Practice {
	int day_end_fallow;
	bool to_apply(Plot plot, int current_day) {
		return (current_day = day_end_fallow);
	}
	action effect(Plot plot) {
		// 1. Pest Break: Pests starve during fallow
    	plot.pest_load <- plot.pest_load * (1.0 - pest_reduction_fallow); 
    
    	// 2. Soil Regeneration
   		ask plot { do update_soil_status(true); }
	}
}

species Sowing_practice parent: Practice { 
	map<int,bool> implementation_days;
	string name <- "sowing";
	Cultivar type_of_cultivar;
	bool mechanical_seeding;
	float labor <- mechanical_seeding ? (labor_sowing_machine_hours + labor_land_prep_hours_meca) : (labor_sowing_manual_hours + labor_land_prep_hours_manual);
			
	bool to_apply(Plot plot, int current_day) { 
		bool impl_day <- current_day in implementation_days.keys;
		if (impl_day and implementation_days[current_day]) {
			plot.last_harvest_date <- nil; 
		}
		plot.date_sowing_ok <- plot.date_sowing_ok or impl_day;
		return plot.date_sowing_ok and (plot.associated_crop = nil); 
	} 
	
	action effect(Plot plot) {
		plot.date_sowing_ok <- false;
		ready_to_end_season <- true; 
		plot.the_farmer.ended_season <- false;
		plot.last_variety <- type_of_cultivar;
		plot.last_harvest_was_aqua <- false;
		 
		create Crop (the_farmer: plot.the_farmer, variety: type_of_cultivar, is_aquaculture: false) {
			seed_density_kg_ha <- myself.mechanical_seeding ? seed_density_kg_ha_mechanical : seed_density_kg_ha_broadcast;
			plot.associated_crop <- self;
			concerned_plot <- plot;  
			
			// Agro-ecological synergy: if the previous season on this plot was aquaculture,
			// organic sediment provides a free starter nitrogen bonus to the rice crop.
			if (plot.has_shrimp_nutrient_bonus) {
				nitrogen_stock <- nitrogen_stock + shrimp_organic_n_bonus;
				plot.has_shrimp_nutrient_bonus <- false;
			}

			Practice p <- plot.the_farmer.practice.has_practice(PESTICIDE) ? plot.the_farmer.practice.get_practice(PESTICIDE) : nil;
			if (p != nil) {
				Pesticide_application_practice pp <- Pesticide_application_practice(p);
				plot.pesticide_threshold <- pp.pesticide_thresholds[pp.pesticide_thresholds.keys with_min_of (abs(each - current_date.day_of_year))];
			}
			p <- plot.the_farmer.practice.has_practice(INPUT) ? plot.the_farmer.practice.get_practice(INPUT) : nil;
			if (p != nil) {
				Input_use_practice pp <- Input_use_practice(p);
				plot.target_nitrogen <- pp.target_nitrogens[pp.target_nitrogens.keys with_min_of (abs(each - current_date.day_of_year))];
				plot.trigger_threshold <- pp.trigger_thresholds[pp.trigger_thresholds.keys with_min_of (abs(each - current_date.day_of_year))];
			}
			thermal_units_total <- variety.tt_emergence + variety.tt_veg + variety.tt_rep + variety.grain_filling_duration;
       		potential_rue_calibrated <- myself.type_of_cultivar.RUE * rue_efficiency_factor; 

       		if (plot.last_harvest_date != nil) { 
	           if (plot.leftover_straw_base > 0.0) {
	       			int rest_days <- round((current_date - plot.last_harvest_date) / #day);
	        		if (rest_days < safe_rest_period) {
			            float missing_rest_ratio <- (safe_rest_period - rest_days) / safe_rest_period;
			            float time_factor <- missing_rest_ratio; 
			            float total_penalty <- plot.leftover_straw_base * toxicity_per_straw_unit * time_factor;
			            total_penalty <- min(0.30, total_penalty);
			            float local_toxicity_penalty <- 1.0 - total_penalty;
			            potential_rue_calibrated <- potential_rue_calibrated * local_toxicity_penalty;
			        }  
	   	 		}
	        } 
	         
       		salt_threshold_val <- variety.salinity_tolerance;
       		emergence_threshold <- variety.tt_emergence;
    		flowering_threshold <- emergence_threshold + variety.tt_veg;
     		maturity_threshold <- flowering_threshold + variety.tt_rep;
   
 			concerned_plot.stress_days_salinity <- 0;
    		concerned_plot.stress_days_drought <- 0;
    		concerned_plot.stress_days_flood <- 0; 
    		concerned_plot.stress_days_flood_continuous <- 0; 
    		concerned_plot.pesticide_count <- 0;
    		concerned_plot.max_stress_days_flood_continuous <- 0;  
    		concerned_plot.total_water_pumped <- 0.0;  
    		concerned_plot.final_yield_ton_ha <- 0.0;
    		concerned_plot.straw_yield_ton_ha <- 0.0;
    		concerned_plot.total_fertilizer_applied <- 0.0;
    		concerned_plot.methane_emissions_kg_ha <- 0.0;
    		the_farmer.accumulated_labor_hours <- 0.0;
    		the_farmer.mechanization_costs <- (myself.mechanical_seeding ? mech_cost_sust_fixed : mech_cost_bau_fixed);
   		}
   	}
}


species Harvesting_practice parent: Practice {
	string name <- "harvesting";
	float labor <- labor_harvest_supervision_logistics;
	bool collect_straw; // false (Slash-and-burn) vs 1M: true (Sale)
    
	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil 
		       and not plot.associated_crop.is_aquaculture 
		       and (plot.associated_crop.growth_stage >= 1 or plot.associated_crop.is_dead);
	}
	
 	action effect(Plot plot) {
		// 1. Get the base Harvest Index
        float current_HI <- plot.associated_crop.variety.harvest_index_potential;
       
        if (plot.associated_crop.cumulative_salt_stress_ripening > salinity_sterility_threshold) {
            float sterility_penalty <- (plot.associated_crop.cumulative_salt_stress_ripening * sterility_penalty_rate); 
            sterility_penalty <- min(sterility_penalty, max_sterility_penalty); 
            current_HI <- current_HI * (1.0 - sterility_penalty);
        } 

		plot.associated_crop.cumulative_salt_stress_ripening <- 0.0;
        
        // 2. Calculate dry yield with the dynamic HI and Soil Health
        float dry_yield <- plot.associated_crop.biomass * current_HI * plot.soil_health;
       	
        // Update soil status: "False" because we just harvested a rice crop
        ask plot { do update_soil_status(false); }
        
        plot.final_yield_ton_ha <- (dry_yield * biomass_to_ton_conv) / harvest_moisture_adjust;
        plot.straw_yield_ton_ha <- (plot.associated_crop.biomass * biomass_to_ton_conv) - plot.final_yield_ton_ha; 
 		plot.actual_sold_yield <- plot.final_yield_ton_ha * (1.0 - harvest_loss_rate);

      	float straw_rev <- 0.0;  
        
        // ======================================================================
        // DYNAMIC ECONOMIC ACCOUNTING (Smoothed over the Ripening Phase)
        // ======================================================================
        float avg_humidity_end <- the_weather.humidity; 
        float total_rain_end <- the_weather.rain;
        
        if (plot.days_ripening > 0) {
            avg_humidity_end <- plot.sum_humidity_ripening / plot.days_ripening;
            total_rain_end <- plot.sum_rain_ripening;
        }

        bool is_field_flooded <- plot.water_level > wet_harvest_water_threshold or total_rain_end > wet_harvest_rain_threshold;
        plot.is_high_humidity <- avg_humidity_end > high_humidity_harvest_threshold or total_rain_end > high_humidity_rain_threshold;

        bool actual_collect_straw <- collect_straw;
        if (is_field_flooded) {
            actual_collect_straw <- false; 
        } 
		
		if (collect_straw and actual_collect_straw) { 
			straw_rev <- (plot.straw_yield_ton_ha * 1000) * straw_market_price * the_market.r_straw[current_date.year]; 
		} else { 
    		plot.methane_emissions_kg_ha <- plot.methane_emissions_kg_ha + plot.straw_yield_ton_ha * straw_burn_emission_factor;
		}
		
        plot.sum_tmin_ripening <- 0.0;
    	plot.sum_humidity_ripening <- 0.0;
    	plot.sum_rain_ripening <- 0.0;
    	plot.days_ripening <- 0;
    	 
        plot.the_farmer.revenue <- straw_rev;
         
        float cost_labor <- plot.the_farmer.accumulated_labor_hours * labor_cost_per_hour * (current_date.year in the_market.r_labor.keys ? the_market.r_labor[current_date.year] : 1.0);
        float cost_fert <- plot.total_fertilizer_applied * fertilizer_unit_price * (current_date.year in the_market.r_fertilizer.keys ? the_market.r_fertilizer[current_date.year] : 1.0);
        float cost_pest <- plot.pesticide_count * pesticide_unit_cost * (current_date.year in the_market.r_pesticides.keys ? the_market.r_pesticides[current_date.year] : 1.0);
        float cost_water <- plot.total_water_pumped * pumping_cost_per_mm * (current_date.year in the_market.r_water.keys ? the_market.r_water[current_date.year] : 1.0); 
        float cost_seed <- plot.associated_crop.seed_density_kg_ha * plot.associated_crop.variety.seed_unit_cost * the_market.r_for_seed(plot.associated_crop.variety); 
        float cost_meca <- plot.the_farmer.mechanization_costs * (current_date.year in the_market.r_mech.keys ? the_market.r_mech[current_date.year] : 1.0);   
    	
   		if (plot.is_high_humidity) { 
        	cost_pest <- cost_pest * fungicide_surcharge_factor;
   		}
   		if (is_field_flooded) { 
        	cost_meca <- cost_meca * muddy_harvest_logistics_factor;
   	 	}
		plot.the_farmer.total_costs <- cost_labor + cost_fert + cost_pest + cost_water + cost_meca + cost_seed;
	} 
}

species Irrigating_practice parent: Practice virtual: true {
	float manage_water_needed(Plot plot) virtual: true;
	float pumping_capacity;
	float pumping_energy_cost;
	
	// Only applies to plant crops (Rice)
	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil and not plot.associated_crop.is_aquaculture;
	}
	
	action effect(Plot plot) {
     	float water_needed <- max(0, manage_water_needed(plot));
       
        bool water_is_good_quality <- plot.my_cell.salinity_level < max_pumping_salinity;
        bool water_is_available <- (rain_last_days > min_rain_for_access) and (total_province_pumping < max_province_pumping_capacity);
      
        float water_pumped <- (water_is_good_quality and water_is_available) ? water_needed : 0.0;
       
 		plot.water_level <- plot.water_level + water_pumped;
        plot.associated_crop.water_pumped_today <- water_pumped; 
        if (water_pumped > 0) {  
        	plot.total_water_pumped <- plot.total_water_pumped + water_pumped;
        }
        
      	if (plot.water_level > flood_stress_threshold) {
        	plot.water_level <- plot.water_level - pumping_capacity;
       		plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + (pumping_energy_cost * pumping_cost_per_mm); 
        }
	} 
}

species no_Irrigating_practice parent: Irrigating_practice {
	float manage_water_needed(Plot plot) {
		return 0.0;
	}
}

species CF_Irrigating_practice parent: Irrigating_practice {
	string name <- CF;
	float labor <- daily_labor_water_cf;
	float pumping_capacity <- pumping_capacity_bau;
	float pumping_energy_cost;
	float manage_water_needed(Plot plot) {
		float water_needed <- 0.0;
		if (plot.water_level < water_target_flooded) { 
			water_needed <- water_target_flooded - plot.water_level; 
		}
	   	return water_needed;
	} 
}

species AWD_Irrigating_practice parent: Irrigating_practice {
	string name <- AWD;
	float labor <- daily_labor_water_awd;
	float AWD_threshold <- 0.5;
    float irrigation_amount <- 40.0;
	float pumping_capacity <- pumping_capacity_sust;
	
	float manage_water_needed(Plot plot) {
		float water_needed <- 0.0;
		if (plot.water_level <= awd_pumping_threshold) {
			water_needed <- water_target_flooded - plot.water_level; 
		}
        return water_needed;  
	}
}

species Pesticide_application_practice parent: Practice {
	string name <- PESTICIDE;
	map<int,float> pesticide_thresholds;
	bool mechanical;
	float labor <- mechanical ? labor_spray_drone_hours : labor_spray_manual_hours;
	
	bool to_apply(Plot plot, int current_day) {
		if (plot.associated_crop = nil or plot.associated_crop.is_aquaculture) {
			return false;
		}
		plot.days_since_last_spray <- plot.days_since_last_spray + 1;
		return plot.pest_load > plot.pesticide_threshold and plot.days_since_last_spray >= pest_spray_cooldown_days;
	}
	action effect(Plot plot) {
		plot.days_since_last_spray <- 0;
		plot.pest_load <- 0.0;  
        plot.my_cell.pollution_level <- plot.my_cell.pollution_level + pesticide_pollution_add * plot.shape.area / plot.my_cell.shape.area;
       	plot.pesticide_count <- plot.pesticide_count + 1; 
    	if (mechanical) {
        	plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + cost_service_drone_spray;
        }
        plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor;
	}  
}

species Input_use_practice parent: Practice {
	string name <- INPUT;
	map<int,float> trigger_thresholds;   
	float base_dose;           
	map<int,float> target_nitrogens;
	bool mechanical;
	float labor <- mechanical ? labor_fertilizer_machine_hours : labor_fertilizer_manual_hours;
	
	bool to_apply(Plot plot, int current_day) {
		float soil_degradation <- 1.0 - plot.soil_health; 
		float dynamic_n_goal <- plot.target_nitrogen * (1.0 + soil_degradation);
		
		return plot.associated_crop != nil 
		       and not plot.associated_crop.is_aquaculture
		       and not plot.associated_crop.is_dead
		       and plot.associated_crop.nitrogen_stock < (plot.trigger_threshold * (1.0 + soil_degradation))
		       and plot.total_fertilizer_applied < dynamic_n_goal 
		       and plot.associated_crop.growth_stage < n_late_stage_limit;
	}
	
	action effect(Plot plot) {
        float degradation_gap <- 1.0 - plot.soil_health;
        float compensatory_factor <- 1.0 + degradation_gap;
        float amount <- base_dose * compensatory_factor; 
        
        if ((plot.total_fertilizer_applied + amount) > plot.target_nitrogen) {
        	amount <- plot.target_nitrogen - plot.total_fertilizer_applied;
        }
        
        if (amount > 0) {
	        plot.associated_crop.nitrogen_stock <- plot.associated_crop.nitrogen_stock + amount;
	        plot.total_fertilizer_applied <- plot.total_fertilizer_applied + amount;
        }
	} 
}


// ======================================================================
// AQUACULTURE-SPECIFIC PRACTICES (Strictly applied to Shrimp / Fish)
// ======================================================================

/**
 * Practice managing the stocking of post-larvae or fingerlings at the start of the aquaculture season.
 */
species Aqua_Stocking_practice parent: Practice {
	map<int,bool> implementation_days;
	string name <- "aqua_stocking";
	Aqua_species target_aqua_species;
	float labor <- labor_pond_prep_hours;

	bool to_apply(Plot plot, int current_day) {
		bool impl_day <- current_day in implementation_days.keys;
		if (impl_day and implementation_days[current_day]) {
			plot.last_harvest_date <- nil;
		}
		plot.date_aqua_stocking_ok <- plot.date_aqua_stocking_ok or impl_day;
		return plot.date_aqua_stocking_ok and (plot.associated_crop = nil);
	}

	action effect(Plot plot) {
		plot.stress_days_shallow_water <- 0;
		plot.date_aqua_stocking_ok <- false;
		ready_to_end_season <- true;
		plot.the_farmer.ended_season <- false;
		plot.last_aqua_variety <- target_aqua_species;
		plot.last_harvest_was_aqua <- true;
		ask plot.my_cell {
			do change_protection_status(false);
		}
		create Crop (
			the_farmer: plot.the_farmer,
			aqua_variety: target_aqua_species,
			is_aquaculture: true
		) {
			plot.associated_crop <- self;
			concerned_plot <- plot;
			thermal_units_total <- myself.target_aqua_species.tt_maturity;
			seed_density_kg_ha <- myself.target_aqua_species.default_stocking_density;

			// Initial feed/probiotic pool in the pond
			nitrogen_stock <- aqua_initial_feed_stock;

			// Reset plot seasonal counters
			concerned_plot.stress_days_salinity <- 0;
			concerned_plot.stress_days_drought <- 0;
			concerned_plot.stress_days_flood <- 0;
			concerned_plot.stress_days_flood_continuous <- 0;
			concerned_plot.max_stress_days_flood_continuous <- 0;
			concerned_plot.pesticide_count <- 0;
			concerned_plot.total_water_pumped <- 0.0;
			concerned_plot.final_yield_ton_ha <- 0.0;
			concerned_plot.straw_yield_ton_ha <- 0.0;
			concerned_plot.total_fertilizer_applied <- 0.0;
			concerned_plot.methane_emissions_kg_ha <- 0.0;

			// Reset labor and set pond trenching / preparation mechanization cost
			the_farmer.accumulated_labor_hours <- 0.0;
			the_farmer.mechanization_costs <- mech_cost_shrimp_pond_prep;
		}
	}
}

/**
 * Practice managing the harvest and farm-level accounting of aquaculture species.
 */
species Aqua_Harvesting_practice parent: Practice {
	string name <- "aqua_harvesting";
	float labor <- labor_shrimp_harvest;

	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil 
		       and plot.associated_crop.is_aquaculture 
		       and (plot.associated_crop.growth_stage >= 1.0 or plot.associated_crop.is_dead);
	}

	action effect(Plot plot) {
		ask plot.my_cell {
			do change_protection_status(true);
		}
		Aqua_species sp <- plot.associated_crop.aqua_variety;

		// 1. Convert biomass (g/m²) to commercial yield (tons/ha)
		plot.final_yield_ton_ha <- plot.associated_crop.biomass * biomass_to_ton_conv;
		plot.straw_yield_ton_ha <- 0.0;
		plot.actual_sold_yield <- plot.final_yield_ton_ha * (1.0 - aqua_harvest_loss_rate);

		// 2. Soil regeneration & organic nutrient bonus for the subsequent rice crop
		ask plot { do update_soil_status(true); }
		plot.has_shrimp_nutrient_bonus <- true;

		// 3. Economic accounting for the aquaculture cycle
		float r_lab <- (current_date.year in the_market.r_labor.keys) ? the_market.r_labor[current_date.year] : 1.0;
		float r_wat <- (current_date.year in the_market.r_water.keys) ? the_market.r_water[current_date.year] : 1.0;
		float r_mec <- (current_date.year in the_market.r_mech.keys) ? the_market.r_mech[current_date.year] : 1.0;
		float r_fer <- (current_date.year in the_market.r_fertilizer.keys) ? the_market.r_fertilizer[current_date.year] : 1.0;

		float cost_labor <- plot.the_farmer.accumulated_labor_hours * labor_cost_per_hour * r_lab;
		float cost_post_larvae <- plot.associated_crop.seed_density_kg_ha * sp.stocking_unit_cost;
		float cost_feed <- plot.total_fertilizer_applied * aqua_feed_unit_price * r_fer;
		float cost_water <- plot.total_water_pumped * pumping_cost_per_mm * r_wat;
		float cost_meca <- plot.the_farmer.mechanization_costs * r_mec;

		plot.the_farmer.revenue <- 0.0; // Sales revenue is computed by the Market agent at season end
		plot.the_farmer.total_costs <- cost_labor + cost_post_larvae + cost_feed + cost_water + cost_meca;
	}
}


/**
 * Practice managing brackish water pumping and pond depth maintenance during the aquaculture season.
 */
species Aqua_Irrigating_practice parent: Practice {
    string name <- "aqua_irrigation";
    float pumping_capacity <- pumping_capacity_sust;
    float internal_saline_water_buffer <- 0.0;
    float max_buffer_capacity <- 150.0;

    bool to_apply(Plot plot, int current_day) {
        return plot.associated_crop != nil and plot.associated_crop.is_aquaculture;
    }
    
    float manage_water_needed(Plot plot) {
        if (plot.associated_crop = nil) { return 0.0; }
        float target_depth <- plot.associated_crop.aqua_variety.min_water_level + 50.0;
        return (plot.water_level < target_depth) ? (target_depth - plot.water_level) : 0.0;
    }

    action effect(Plot plot) {
        if (plot.associated_crop = nil) { return; }

        float water_needed <- max(0.0, manage_water_needed(plot));
        Aqua_species sp <- plot.associated_crop.aqua_variety;
        float canal_salinity <- plot.my_cell.salinity_level;

        bool optimal_canal_water <- (canal_salinity >= sp.salinity_opt_min and canal_salinity <= sp.salinity_opt_max);
        bool tolerable_canal_water <- (canal_salinity >= sp.salinity_min and canal_salinity <= sp.salinity_max);

        float water_in <- 0.0;

        if (optimal_canal_water) {
            water_in <- min(pumping_capacity, water_needed + 20.0);
            internal_saline_water_buffer <- min(max_buffer_capacity, internal_saline_water_buffer + 15.0);
        } else if (tolerable_canal_water) {
            water_in <- min(pumping_capacity, water_needed);
        } else {
            // Canal water is suboptimal: first draw from buffer if available
            if (internal_saline_water_buffer > 0.0) {
                float buffer_release <- min(internal_saline_water_buffer, water_needed);
                plot.water_level <- plot.water_level + buffer_release;
                internal_saline_water_buffer <- internal_saline_water_buffer - buffer_release;
                water_needed <- max(0.0, water_needed - buffer_release);
            }
            // Survival pumping: if water level drops below minimum threshold, pump anyway to prevent desiccation
            if (plot.water_level < sp.min_water_level) {
                water_in <- min(pumping_capacity, sp.min_water_level - plot.water_level);
            }
        }

        if (water_in > 0.0) {
            plot.water_level <- plot.water_level + water_in;
            plot.associated_crop.water_pumped_today <- water_in;
            plot.total_water_pumped <- plot.total_water_pumped + water_in;
        }

        plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + daily_labor_aqua_water;
    }
}

/**
 * Practice managing supplemental feeding / probiotics during the aquaculture season.
 */
species Aqua_Feeding_practice parent: Practice {
	string name <- "aqua_feeding";
	float trigger_threshold;
	float base_dose;
	float target_feed;
	float labor <- 1.0;

	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil
		       and plot.associated_crop.is_aquaculture
		       and not plot.associated_crop.is_dead
		       and plot.associated_crop.nitrogen_stock < trigger_threshold
		       and plot.total_fertilizer_applied < target_feed;
	}

	action effect(Plot plot) {
		Aqua_species sp <- plot.associated_crop.aqua_variety;
		float amount <- min(base_dose, target_feed - plot.total_fertilizer_applied);
		if (amount > 0.0) {
			plot.associated_crop.nitrogen_stock <- plot.associated_crop.nitrogen_stock + amount;
			plot.total_fertilizer_applied <- plot.total_fertilizer_applied + amount;
			float r_feed <- (current_date.year in the_market.r_aqua_feed.keys) ? the_market.r_aqua_feed[current_date.year] : 1.0;

			float cost_post_larvae <- plot.associated_crop.seed_density_kg_ha * sp.stocking_unit_cost * the_market.r_for_aqua_stocking(sp);
			float cost_feed <- plot.total_fertilizer_applied * aqua_feed_unit_price * r_feed;
		}
		
	}
}


// ======================================================================
// GENERIC CROP STRATEGY DEFINITION
// ======================================================================

species Agricultural_strategy virtual: false {
	string id;  // Unique identifier for the practice
	string short_name; // Short name used for displays
	rgb color;  // Color used for visual representation
	
	// Rice / Plant core practices
	Sowing_practice sowing;
	Harvesting_practice harvesting;
	Irrigating_practice irrigation;
	
	// Optional Aquaculture core practices (for rotational or pure aquaculture strategies)
	Aqua_Stocking_practice aqua_stocking;
	Aqua_Harvesting_practice aqua_harvesting;
	
	list<Practice> other_practices; 
	map<string, Practice> practices_id;
	bool is_active_season <- false;
	
	map<string, list<float>> seasons_summary <- map((key_indicators + (expense_categories.keys collect("Expense: "+each))) collect(each::list<float>([]))); 
	map<string, list<float>> year_summary <- map(
		((key_indicators - ["Current season"] + (expense_categories.keys collect("Expense: "+each))) collect(each::[each="Current year"?current_date.year:0.0]))
	); 
	float practice_area <- 1.0;
	float day_income <- 0.0;
	float day_expenses <- 0.0;
	float total_balance <- 0.0;
	float balance_per_ha <- 0.0;
	
	float market_price;
	float fert_cost;
	float seed_cost;
	float other_cost;
 	list<int> activity <- [];
	
	action initialize() {
		practices_id <- (other_practices as_map (each.name :: each));
		if (sowing != nil) { practices_id[sowing.name] <- sowing; }
		if (harvesting != nil) { practices_id[harvesting.name] <- harvesting; }
		if (aqua_stocking != nil) { practices_id[aqua_stocking.name] <- aqua_stocking; }
		if (aqua_harvesting != nil) { practices_id[aqua_harvesting.name] <- aqua_harvesting; }
	} 
	 
	bool has_practice(string practice_id) {
		return practice_id in practices_id.keys;
	}
	Practice get_practice(string practice_id) {
		return practices_id[practice_id];
	}
	
	action switch_to_new_year() {
		loop key over: seasons_summary.keys - ["Current year","Current season"] {
			year_summary[key] <- year_summary[key] + 0.0;
		}
		year_summary["Current year"] <+ current_date.year;
		do compute_practice_area(); 
	}
	
	action compute_practice_area() {
		practice_area <- plot_species where(each.the_farmer.practice = self) sum_of(each.surface_in_ha);
		year_summary["Crop area"][length(year_summary["Crop area"]) - 1] <- practice_area;
	}

	action add_to_indicator(string indicator, float val) {
		if !(indicator in year_summary.keys) {
			write "ERROR in year summary: "+indicator+" not in "+year_summary.keys;
		}
		if !(indicator in seasons_summary.keys) {
			write "ERROR in seasons summary: "+indicator+" not in "+year_summary.keys;
		}
		list<float> l <- seasons_summary[indicator];
		l[length(l) - 1] <- last(l) + val;
		seasons_summary[indicator] <- l;
		
		list<float> l2 <- year_summary[indicator];
		l2[length(l2) - 1] <- last(l2) + val;
		year_summary[indicator] <- l2;
	}
	
	list<string> create_x_labels() {
		list<string> tmp <- [];
		loop i from: 0 to: length(seasons_summary["Current season"] - 1) {
			tmp <+ 'Y'+seasons_summary["Current year"][i]+"S"+seasons_summary["Current season"][i];
		}
		return tmp;
	}
}


// ======================================================================
// SPECIFIC STRATEGIES
// ======================================================================

species BAU_rice_3_season parent: Agricultural_strategy {
	string id <- BAU_3S;
	string short_name <- "Business as usual - 3 seasons";
	rgb color <- practices_color[id];

	list<Practice> other_practices;
	init {
		sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451), three_seasons_sowing, false);
		harvesting <- world.create_harvesting_practice(false);
		ask world {
			do add_CF_practice(myself);
			map<int,float> ftr;
			map<int,float> fta;
			map<int,float> pta;
			loop i from: 0 to: length(three_seasons_sowing) - 1 {
				ftr[three_seasons_sowing.keys[i]] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_3_seasons[i];
				fta[three_seasons_sowing.keys[i]] <- bau_nitrogen_goal * fert_targets_coeff_3_seasons[i];
				pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
			}
			do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);			
			do add_pesticide_practice(myself, pta, false, false); 
		} 
		do initialize();
	}
} 

species BAU_rice_3_season_AWD parent: Agricultural_strategy {
	string id <- BAU_3S_AWD;
	string short_name <- "Business as usual - 3 seasons with AWD";
	rgb color <- practices_color[id];

	list<Practice> other_practices;
	init {
		sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451), three_seasons_sowing, false);
		harvesting <- world.create_harvesting_practice(false);
		ask world {
			do add_AWD_practice(myself);
			map<int,float> ftr;
			map<int,float> fta;
			map<int,float> pta;
			loop i from: 0 to: length(three_seasons_sowing) - 1 {
				ftr[three_seasons_sowing.keys[i]] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_3_seasons[i];
				fta[three_seasons_sowing.keys[i]] <- bau_nitrogen_goal * fert_targets_coeff_3_seasons[i];
				pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
			}
			do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);			
			do add_pesticide_practice(myself, pta, false, false); 
		} 
		do initialize();
	}
}

species Custom_practices parent: Agricultural_strategy {
	string id <- CUSTOM;
	string short_name <- "Custom practices";
	rgb color <- practices_color[id];

	list<Practice> other_practices;
	init {
		sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451), three_seasons_sowing, false);
		harvesting <- world.create_harvesting_practice(false);
		ask world {
			do add_CF_practice(myself);
			map<int,float> ftr;
			map<int,float> fta;
			map<int,float> pta;
			loop i from: 0 to: length(three_seasons_sowing) - 1 {
				ftr[three_seasons_sowing.keys[i]] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_3_seasons[i];
				fta[three_seasons_sowing.keys[i]] <- bau_nitrogen_goal * fert_targets_coeff_3_seasons[i];
				pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
			}
			do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);			
			do add_pesticide_practice(myself, pta, false, false); 	
		} 
		do initialize();
	}
}

species BAU_rice_2_season parent: Agricultural_strategy {
	string id <- BAU_2S;
	string short_name <- "Business as usual - 2 seasons";
	rgb color <- practices_color[id];

	list<Practice> other_practices;
	init {
		sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451), two_seasons_sowing, false);
		harvesting <- world.create_harvesting_practice(false);
		ask world {
			do add_CF_practice(myself);
			map<int,float> ftr;
			map<int,float> fta;
			map<int,float> pta;
			loop i from: 0 to: length(two_seasons_sowing) - 1 {
				ftr[two_seasons_sowing.keys[i]] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_2_seasons[i];
				fta[two_seasons_sowing.keys[i]] <- bau_nitrogen_goal * fert_targets_coeff_2_seasons[i];
				pta[two_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_2_seasons[i];
			}
			do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);			
			do add_pesticide_practice(myself, pta, false, false); 	
			do add_fallow_practice(myself, fallow_day);
		} 
		do initialize();
	}
} 

species OMH_rice parent: Agricultural_strategy {
	string id <- OMRH;
	string short_name <- "One Million Hectares";
	rgb color <- practices_color[id];

	list<Practice> other_practices;
	init {
		sowing <- world.create_sowing_practice(Cultivar first_with (each.name = ST25), two_seasons_sowing, true);
		harvesting <- world.create_harvesting_practice(true);
		ask world {
			do add_AWD_practice(myself);
			map<int,float> ftr;
			map<int,float> fta;
			map<int,float> pta;
			loop i from: 0 to: length(two_seasons_sowing) - 1 {
				ftr[two_seasons_sowing.keys[i]] <- sust_n_trigger_threshold * fert_trigger_thresholds_coeff_2_seasons[i];
				fta[two_seasons_sowing.keys[i]] <- sust_nitrogen_goal * fert_targets_coeff_2_seasons[i];
				pta[two_seasons_sowing.keys[i]] <- sust_pesticide_threshold * pesticide_thresholds_2_seasons[i];
			}
			do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: sust_n_dose_amount, targets: fta, mech: false);			
			do add_pesticide_practice(myself, pta, true, true); 	
			do add_fallow_practice(myself, fallow_day);
		} 
		do initialize();
	}
}

/**
 * Complete Strategy Definition: Rice-Shrimp Rotational System
 * Reuses existing standard Rice practices for the wet season (Day 210)
 * and combines them with dedicated Aquaculture practices for the dry season (Day 35).
 */
species Rice_Shrimp_strategy parent: Agricultural_strategy {
    string id <- RICE_SHRIMP;
    string short_name <- "Rice-Shrimp Rotation (Lua-Tom)";
    rgb color <- practices_color[id];

    list<Practice> other_practices;

    init {
        int shrimp_day <- 35; // Dry season stocking (early February)
        int rice_day <- 210;  // Wet season sowing (late July)

        // 1. Standard Rice Practices (for the wet season)
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = ST25), [rice_day::true], true);
        harvesting <- world.create_harvesting_practice(true);

        // 2. Aquaculture-specific Practices (for the dry brackish season)
        aqua_stocking <- world.create_aqua_stocking_practice(Aqua_species first_with (each.name = "PENAEUS_MONODON"), [shrimp_day::true]);
        aqua_harvesting <- world.create_aqua_harvesting_practice();

        ask world {
            // Standard AWD irrigation for the rice season (automatically inactive during shrimp season)
            do add_AWD_practice(myself);

            // Standard Fertilizer input for the rice season (reduced target thanks to shrimp organic waste)
            do add_input_use_practice(
                cp: myself,
                trigger_thresholds_: [rice_day::sust_n_trigger_threshold],
                base_dose_: sust_n_dose_amount,
                targets: [rice_day::(sust_nitrogen_goal * 0.6)],
                mech: false
            );

            // Specific Aquaculture irrigation and feeding practices (automatically active only during shrimp season)
            do add_aqua_irrigating_practice(myself);
            do add_aqua_feeding_practice(myself, 10.0, 20.0, 60.0);
        }
        do initialize();
    }
}