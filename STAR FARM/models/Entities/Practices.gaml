/**
 * ================================================================================================
 * Name: STARFARM
 * Description:
 *   This model defines the agricultural practices used in the STARFARM simulation framework.
 *   It establishes the structure and initialization of different crop management strategies
 *   (e.g., Continuous Flooding and Alternate Wetting and Drying for rice cultivation).
 *
 *   The practices are used to parameterize crop agents with economic data, irrigation
 *   and fertilization schedules, and sowing/harvesting periods. Each practice can also
 *   store results from external crop growth models (e.g., ORYZA) for integration with
 *   simulated dynamics.
 *
 * Based on: the internal empty template
 * Author: Patrick Taillandier
 * Tags: crop management, practices, rice, STARFARM
 *
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
	map<string,Crop_strategy> practices;
	
	// List of the indicators to be monitored
	list<string> key_indicators <- ["Harvest","Profit","Crop area","Water consumption","Fertilizer consumption","Current year","Current season"];
	// List of the expense categories, and the corresponding color for display
	map<string,rgb> expense_categories <- ["Seed"::rgb(22, 160, 133),"Fertilizer"::rgb(241, 196, 15),"Irrigation"::rgb(52, 152, 219),"Manpower"::rgb(230, 126, 34),"Other"::rgb(127, 140, 141)];
	int season_spring_3s <- 320;
	int season_autumn_3s <- 95;
	int season_winter_3s <- 215;
	int season_spring_2s <- 305;
	int season_autumn_2s <- 115;
	list<float> fert_trigger_thresholds_coeff_3_seasons <- [0.9, 1.0,1.2];
	list<float> fert_targets_coeff_3_seasons <- [1.3, 1.3,0.8];
	list<float> fert_trigger_thresholds_coeff_2_seasons <- [0.8, 1.0];
	list<float> fert_targets_coeff_2_seasons <- [1.2, 1.0];

	list<float> pesticide_thresholds_2_seasons <- [0.4,1.0];		
	list<float> pesticide_thresholds_3_seasons <- [0.4,0.6, 1.6];		
	int fallow_day <- 290;
	
	map<int, bool> three_seasons_sowing ;
	map<int, bool> two_seasons_sowing ;
	
	// Action to create all practice instances from their species definitions
	action create_practices() {
		three_seasons_sowing <- [int(season_spring_3s)::true,int(season_autumn_3s)::false, int(season_winter_3s)::false];
		
		two_seasons_sowing <- [season_spring_2s::true, season_autumn_2s::false];
	
		loop s over: Crop_strategy.subspecies { 
			create s returns: new_practices;
			Crop_strategy ct <- Crop_strategy(first(new_practices));
			practices[ct.id] <- ct ;
		}
		ask Crop_strategy {
			do initialize();
		} 
	}
	
	 
	Sowing_practice create_sowing_practice(Cultivar cultivar, map<int,bool> days_cleaning, bool mechanical) {
		create Sowing_practice (type_of_cultivar: cultivar, implementation_days: days_cleaning,  mechanical_seeding:mechanical) returns: sow_pract;
		return first(sow_pract);
	}
	
	Harvesting_practice create_harvesting_practice (bool collect_straw){
		create Harvesting_practice (collect_straw:collect_straw) returns: har_pract;
		return first(har_pract);
	}	
	 
	action add_AWD_practice(Crop_strategy pract) {
		create AWD_Irrigating_practice  {
			pract.irrigation <- self;
			pract.other_practices << self;
		}
	}
	
	action add_fallow_practice(Crop_strategy pract, int doy_end) {
		create Fallow_practice  {
			day_end_fallow <- doy_end;
			pract.other_practices << self;	
		} 
	}
	
	action add_CF_practice(Crop_strategy pract) {
		create CF_Irrigating_practice  {
			pract.irrigation <- self;
			pract.other_practices << self;
		} 
	}
	
	action add_input_use_practice(Crop_strategy cp, map<int,float>  trigger_thresholds_, float base_dose_, map<int,float> targets, bool mech) {
	    create Input_use_practice {
	        self.trigger_thresholds <- trigger_thresholds_;
	        self.base_dose <- base_dose_;
	        self.target_nitrogens <- targets;
	        self.mechanical <- mech;
	        // Add to the list of practices of the parent
	        cp.other_practices <- cp.other_practices + self;
	    }
	}
	
	action add_pesticide_practice(Crop_strategy pract, map<int,float> pesticide_thresholds, bool mec, bool IPM) {
		create Pesticide_application_practice (pesticide_thresholds:pesticide_thresholds, mechanical:mec){
			pract.other_practices << self;
			ask pract.sowing {
				labor <- labor + (IPM ? labor_IMP_pest_management_hours : labor_pest_management_hours);
			}
		} 
	}
	 
}


species Practice virtual: true {
	float labor;
	bool to_apply(Plot plot, int current_day) {
		return true;
	}
	
	action add_labor(Plot plot) {
		plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor;
	}
	
	action effect_with_labor (Plot plot){
		do effect(plot);
		do add_labor(plot);
	}
	 
	action effect(Plot plot) virtual: true; 
} 

species Fallow_practice parent: Practice {
	
	int day_end_fallow;
	bool to_apply(Plot plot, int current_day) {
		return (current_day = day_end_fallow);
	}
	action effect(Plot plot) {
		// 1. Pest Break : Les pestes meurent de faim
    	plot.pest_load<- plot.pest_load * (1.0 - pest_reduction_fallow); 
    
    	// 2. Soil Regeneration : Le sol se repose (si vous utilisez le module soil_health)
   		 ask plot { do update_soil_status(true); }
    
	}
	
}

species Sowing_practice parent:Practice { 
	map<int,bool> implementation_days ;
	
	string name <- "sowing";
	Cultivar type_of_cultivar;
	bool mechanical_seeding;
	float labor <- mechanical_seeding ? (labor_sowing_machine_hours + labor_land_prep_hours_meca) : (labor_sowing_manual_hours + labor_land_prep_hours_manual);
			
	
	bool to_apply(Plot plot, int current_day) { 
		bool impl_day  <- current_day in implementation_days.keys;
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
		 
		create Crop (the_farmer:plot.the_farmer, variety:type_of_cultivar  ) {
			seed_density_kg_ha <- myself.mechanical_seeding ? seed_density_kg_ha_mechanical : seed_density_kg_ha_broadcast;
			plot.associated_crop <- self;
			concerned_plot <- plot;  
			Practice p <- plot.the_farmer.practice.has_practice(PESTICIDE) ?plot.the_farmer.practice.get_practice(PESTICIDE) : nil;
			if (p != nil) {
				Pesticide_application_practice pp <- Pesticide_application_practice(p);
				plot.pesticide_threshold <- pp.pesticide_thresholds[pp.pesticide_thresholds.keys with_min_of (abs(each - current_date.day_of_year)) ];
			
			}
			p <- plot.the_farmer.practice.has_practice(INPUT) ?plot.the_farmer.practice.get_practice(INPUT) : nil;
			if (p != nil) {
				Input_use_practice pp <- Input_use_practice(p);
				plot.target_nitrogen <- pp.target_nitrogens[pp.target_nitrogens.keys with_min_of (abs(each - current_date.day_of_year)) ];
				plot.trigger_threshold <- pp.trigger_thresholds[pp.trigger_thresholds.keys with_min_of (abs(each - current_date.day_of_year)) ];
			}
			thermal_units_total <- variety.tt_emergence + variety.tt_veg + variety.tt_rep + variety.grain_filling_duration;
       		potential_rue_calibrated <- myself.type_of_cultivar.RUE * rue_efficiency_factor; 

       		
       		if (plot.last_harvest_date != nil) { 
	           // Check if there is fresh straw decomposing in the soil
	           if (plot.leftover_straw_base > 0.0 ) {
	        
	       			 int rest_days <- round((current_date - plot.last_harvest_date) / #day);
	        		
	        		if (rest_days < safe_rest_period) {
	            
			            // 1. Time factor: Non-linear decay of toxicity over time
			            float missing_rest_ratio <- (safe_rest_period - rest_days) / safe_rest_period;
			            float time_factor <- missing_rest_ratio ; 
			            
			            // 2. Calculate the combined penalty: Amount of straw * Toxicity rate * Time factor
			            float total_penalty <- plot.leftover_straw_base * toxicity_per_straw_unit * time_factor;
			            
			            // 3. Safety check: Ensure the penalty doesn't exceed a logical maximum (e.g., 80% reduction max)
			            total_penalty <- min(0.30, total_penalty);
			            
			            // 4. Apply the permanent penalty to the plant's engine (RUE)
			            float local_toxicity_penalty <- 1.0 - total_penalty;
			            potential_rue_calibrated <- potential_rue_calibrated * local_toxicity_penalty;
			        }  
	   	 		}
	           
	            
	        } 
	         
	      
       		
       		salt_threshold_val <- variety.salinity_tolerance;
       		emergence_threshold <- variety.tt_emergence;
    		flowering_threshold <- emergence_threshold + variety.tt_veg;
     		maturity_threshold  <- flowering_threshold + variety.tt_rep;
   
 			 
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



species Harvesting_practice parent:Practice {
	string name <- "harvesting";
	float labor <- labor_harvest_supervision_logistics;
		
	bool collect_straw;             //false (Slash-and-burn) vs 1M: true (Sale)
    
	
	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil and (plot.associated_crop.growth_stage >= 1 or plot.associated_crop.is_dead);
	}
	
	
 	action effect(Plot plot) {
		// 1. Get the base Harvest Index
        float current_HI <- plot.associated_crop.variety.harvest_index_potential;
       
        if (plot.associated_crop.cumulative_salt_stress_ripening > salinity_sterility_threshold) {
            // Calculate sterility penalty based on cumulative ripening stress
            float sterility_penalty <- (plot.associated_crop.cumulative_salt_stress_ripening * sterility_penalty_rate); 
            
            // Cap the penalty to the maximum biological threshold defined globally
            sterility_penalty <- min(sterility_penalty, max_sterility_penalty); 
            
            // Apply the dynamic sterility penalty to the Harvest Index (HI)
            current_HI <- current_HI * (1.0 - sterility_penalty);
        } 

		plot.associated_crop.cumulative_salt_stress_ripening <- 0.0;
        
              // 3. Calculate dry yield with the dynamic HI
        float dry_yield <- plot.associated_crop.biomass * current_HI;
      	
    	//float dry_yield <- plot.associated_crop.biomass * plot.associated_crop.variety.harvest_index_potential;
	  
	  	// Applying the Soil Fatigue Factor ---
        dry_yield <- dry_yield * plot.soil_health;
       	
        // Update soil status: "False" because we just harvested a crop (it was not fallow)
        ask plot { do update_soil_status(false); }
        
        plot.final_yield_ton_ha <- (dry_yield * biomass_to_ton_conv) / harvest_moisture_adjust;
        plot.straw_yield_ton_ha <- (plot.associated_crop.biomass * biomass_to_ton_conv) -  plot.final_yield_ton_ha; 
 
 		plot.actual_sold_yield <- plot.final_yield_ton_ha * (1.0 - harvest_loss_rate);

		//float rice_rev <- (actual_sold_yield * 1000) * plot.associated_crop.variety.rice_market_price * the_market.r_for_crop(plot.associated_crop.variety) ;
      	float straw_rev <- 0.0;  
        
       
		
		
		  // ======================================================================
        // DYNAMIC ECONOMIC ACCOUNTING (Smoothed over the Ripening Phase)
        // ======================================================================
        float avg_humidity_end <- the_weather.humidity; 
        float total_rain_end <- the_weather.rain;
        
        // Safeguard to compute averages over the ripening period
        if (plot.days_ripening > 0) {
            avg_humidity_end <- plot.sum_humidity_ripening / plot.days_ripening;
            total_rain_end <- plot.sum_rain_ripening;
        }

        // Condition 1: Muddy or Flooded Field 
        // Checks if the field is currently flooded OR if it rained a lot (> 40mm) in the last few weeks
        bool is_field_flooded <- plot.water_level > wet_harvest_water_threshold or total_rain_end > wet_harvest_rain_threshold;
        
        // Condition 2: High Humidity / Fungal Risk
        // Checks if the average humidity during the whole ripening phase was very high
        
        plot.is_high_humidity <- avg_humidity_end > high_humidity_harvest_threshold or total_rain_end > high_humidity_rain_threshold;

        // 2. Straw Loss (Circular Economy failure)
        bool actual_collect_straw <- collect_straw;
        if (is_field_flooded) {
            actual_collect_straw <- false; 
        } 
		
		 if (collect_straw and actual_collect_straw) { straw_rev <- (plot.straw_yield_ton_ha * 1000) * straw_market_price * the_market.r_straw[current_date.year] ; }
        
        else { 
   			// Calculate emissions generated by open burning and add to the plot's carbon footprint 
    		plot.methane_emissions_kg_ha <- plot.methane_emissions_kg_ha +  plot.straw_yield_ton_ha * straw_burn_emission_factor;
		}
		
        plot.sum_tmin_ripening <- 0.0;
    	plot.sum_humidity_ripening <- 0.0;
    	plot.sum_rain_ripening <- 0.0;
    	plot.days_ripening <- 0;
    	 
    	
        plot.the_farmer.revenue <- straw_rev;
         
        float cost_labor <- plot.the_farmer.accumulated_labor_hours * labor_cost_per_hour * (current_date.year in the_market.r_labor.keys? the_market.r_labor[current_date.year] : 1.0);
        float cost_fert <- plot.total_fertilizer_applied * fertilizer_unit_price * (current_date.year in the_market.r_fertilizer.keys? the_market.r_fertilizer[current_date.year] : 1.0);
        float cost_pest <- plot.pesticide_count * pesticide_unit_cost * (current_date.year in the_market.r_pesticides.keys? the_market.r_pesticides[current_date.year] : 1.0);
        float cost_water <- plot.total_water_pumped * pumping_cost_per_mm * (current_date.year in the_market.r_water.keys? the_market.r_water[current_date.year] : 1.0); 
        float cost_seed <- plot.associated_crop.seed_density_kg_ha * plot.associated_crop.variety.seed_unit_cost * the_market.r_for_seed(plot.associated_crop.variety); 
        float cost_meca <- plot.the_farmer.mechanization_costs * (current_date.year in the_market.r_mech.keys? the_market.r_mech[current_date.year] : 1.0);   
    	
    	// Persistent high humidity favors fungal diseases, requiring more expensive curative treatments.
   		 if (plot.is_high_humidity) { 
        	cost_pest <- cost_pest * fungicide_surcharge_factor; // +30% cost
   		}
   		 // Combine harvesters charge a premium to operate in muddy/flooded fields due to risk and fuel consumption.
   		if (is_field_flooded) { 
        	cost_meca <- cost_meca * muddy_harvest_logistics_factor; // +40% cost
   	 	}
		plot.the_farmer.total_costs <- cost_labor+ cost_fert + cost_pest + cost_water + cost_meca ;
       
	} 
}

species Irrigating_practice parent: Practice virtual: true{
	
	float manage_water_needed(Plot plot)  virtual: true;
	float pumping_capacity;
	float pumping_energy_cost;
	bool to_apply(Plot plot, int current_day) {
		// plot.water_level <- plot.water_level + the_weather.rain - daily_water_loss_mm;
      
		return plot.associated_crop != nil;
	}
	
	action effect(Plot plot) {
		 
		 
     	float water_needed <- max(0,manage_water_needed(plot));
       
        bool water_is_good_quality <- plot.my_cell.salinity_level < max_pumping_salinity;
        bool water_is_available <- (rain_last_days > min_rain_for_access) and (total_province_pumping < max_province_pumping_capacity);
      
        float water_pumped <- (water_is_good_quality and water_is_available) ? water_needed: 0.0;
       
 		plot.water_level <- plot.water_level + water_pumped;
       
        plot.associated_crop.water_pumped_today <-  water_pumped; 
        if (water_pumped > 0) {  
        	plot.total_water_pumped <- plot.total_water_pumped + water_pumped;
        }
        
      	if (plot.water_level > flood_stress_threshold) {
        	plot.water_level <- plot.water_level - pumping_capacity;
       		plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + (pumping_energy_cost * pumping_cost_per_mm); 
        }
	} 
}


species no_Irrigating_practice parent: Irrigating_practice{
	float manage_water_needed(Plot plot)  {
		return 0.0;
	}
	
}

species CF_Irrigating_practice parent: Irrigating_practice{
	string name <- CF;
	float labor <- daily_labor_water_cf;
	float pumping_capacity <- pumping_capacity_bau;
	float pumping_energy_cost;
	float manage_water_needed(Plot plot)  {
		float water_needed <- 0.0;
		
		if (plot.water_level < water_target_flooded) { 
			water_needed <- water_target_flooded - plot.water_level; 
		}
	   	return water_needed;
	} 
}

species AWD_Irrigating_practice parent: Irrigating_practice{
	string name <- AWD;
	float labor <- daily_labor_water_awd;
	
	// CERES parameters
	float AWD_threshold <- 0.5;   // fraction of FC triggering irrigation
    float irrigation_amount <- 40.0; // mm per event
	float pumping_capacity <- pumping_capacity_sust;
	
	float manage_water_needed(Plot plot)  {
		float water_needed <- 0.0;
		if (plot.water_level <= awd_pumping_threshold) {
			water_needed <- water_target_flooded - plot.water_level; 
		}
        return water_needed;  
	}
}

species Pesticide_application_practice parent:Practice {
	string name <- PESTICIDE;
	map<int,float> pesticide_thresholds;
	bool mechanical;
	float labor <- mechanical ? labor_spray_drone_hours : labor_spray_manual_hours;
	
	bool to_apply(Plot plot, int current_day) {
		if (plot.associated_crop = nil) {
			return false;
		}
		plot.days_since_last_spray <- plot.days_since_last_spray + 1;
		return plot.pest_load > plot.pesticide_threshold and plot.days_since_last_spray >= pest_spray_cooldown_days;
	}
	action effect(Plot plot) {
		plot.days_since_last_spray <-0;
		plot.pest_load <- 0.0;  
        plot.my_cell.pollution_level <- plot.my_cell.pollution_level + pesticide_pollution_add * plot.shape.area / plot.my_cell.shape.area;
       	plot.pesticide_count <- plot.pesticide_count + 1; 
    	if (mechanical) {
        	plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + cost_service_drone_spray;
        }
        plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor;
	}  
}


species Input_use_practice parent:Practice {
	string name <- INPUT;
	
	map<int,float> trigger_thresholds;   
	float base_dose;           
	
	map<int,float> target_nitrogens;     // Season total limit
	bool mechanical;
	float labor <- mechanical ? labor_fertilizer_machine_hours : labor_fertilizer_manual_hours;
	
	
	// --- DECISION LOGIC ---
	bool to_apply(Plot plot, int current_day) {
		
		// 1. Calculate the loss in soil health 
		float soil_degradation <- 1.0 - plot.soil_health; 
	
		// 3. Calculate the dynamic nitrogen goal
		// The farmer increases the chemical target to compensate for the loss of natural soil fertility.
		// E.g., A BAU farmer with 20% soil degradation changes their goal from 120 kg to 144 kg.
		float dynamic_n_goal <- plot.target_nitrogen * (1.0 + soil_degradation);
		
		return plot.associated_crop != nil 
		       and not plot.associated_crop.is_dead
		       // 1. Check against the SPECIFIC threshold of this practice
		       and plot.associated_crop.nitrogen_stock < (plot.trigger_threshold  * (1.0 + soil_degradation))
		       // 2. Check season limits
		       and plot.total_fertilizer_applied < dynamic_n_goal 
		       and plot.associated_crop.growth_stage < n_late_stage_limit;
	}
	
	// --- ACTION LOGIC ---
	action effect(Plot plot) {
		
		// 1. Calculate the degradation gap (Soil Health Logic)
        float degradation_gap <- 1.0 - plot.soil_health;
        
        // 2. Define compensatory factor
        // they apply more on bad soil effectively.
        float compensatory_factor <- 1.0 + degradation_gap;
        
        // 3. Calculate actual amount using the SPECIFIC BASE DOSE
        float amount <- base_dose * compensatory_factor; 
        
        // Safety check: Don't exceed the season target limit
        if ((plot.total_fertilizer_applied + amount) > plot.target_nitrogen) {
        	amount <- plot.target_nitrogen - plot.total_fertilizer_applied;
        }
        
        // 4. Apply to the crop
        if (amount > 0) {
	        plot.associated_crop.nitrogen_stock <- plot.associated_crop.nitrogen_stock + amount;
	        plot.total_fertilizer_applied <- plot.total_fertilizer_applied + amount;
	        
        }
	} 
}

// ======================================================================
// AQUACULTURE & RICE-SHRIMP ROTATION PRACTICES (Add to Practices.gaml)
// ======================================================================

/**
 * Rotational Sowing/Stocking Practice for Rice-Shrimp systems.
 * Alternates between stocking Shrimp post-larvae in the dry/saline season
 * and sowing Rice in the wet/freshwater season.
 */
species Shrimp_Rice_Sowing_practice parent: Sowing_practice {
    Aqua_species target_aqua_species;
    int shrimp_stocking_day <- 35;  // Early February (onset of saline intrusion)
    int rice_sowing_day <- 210;     // Late July (monsoon flushing of salinity)

    action effect(Plot plot) {
        bool is_shrimp_season <- abs(current_date.day_of_year - shrimp_stocking_day) < 45;

        if (is_shrimp_season) {
            // --- SEASON 1: SHRIMP STOCKING ---
            plot.date_sowing_ok <- false;
            ready_to_end_season <- true;
            plot.the_farmer.ended_season <- false;
            plot.last_aqua_variety <- target_aqua_species;
            plot.last_harvest_was_aqua <- true;

            create Crop (
                the_farmer: plot.the_farmer,
                aqua_variety: target_aqua_species,
                is_aquaculture: true
            ) {
                plot.associated_crop <- self;
                concerned_plot <- plot;
                thermal_units_total <- myself.target_aqua_species.tt_maturity;
                seed_density_kg_ha <- myself.target_aqua_species.default_stocking_density;
                
                // Initial feed/probiotic pool
                nitrogen_stock <- aqua_initial_feed_stock;

                // Reset plot seasonal counters
                concerned_plot.stress_days_salinity <- 0;
                concerned_plot.stress_days_drought <- 0;
                concerned_plot.stress_days_flood <- 0;
                concerned_plot.pesticide_count <- 0;
                concerned_plot.total_water_pumped <- 0.0;
                concerned_plot.final_yield_ton_ha <- 0.0;
                concerned_plot.straw_yield_ton_ha <- 0.0;
                concerned_plot.total_fertilizer_applied <- 0.0;
                concerned_plot.methane_emissions_kg_ha <- 0.0;

                // Economic initialization: Trench dredging and pond preparation
                the_farmer.accumulated_labor_hours <- labor_pond_prep_hours;
                the_farmer.mechanization_costs <- mech_cost_shrimp_pond_prep;
            }
        } else {
            // --- SEASON 2: RICE SOWING (Wet Season) ---
            plot.last_harvest_was_aqua <- false;
            
            // Call standard rice sowing logic from parent Sowing_practice
            invoke effect(plot);
            
            // Explicitly assign the LUA-MD plant growth engine for the rice season
            plot.associated_crop.is_aquaculture <- false;
 
            // Agro-ecological synergy: Shrimp waste provides free organic nitrogen and soil regeneration
            plot.associated_crop.nitrogen_stock <- plot.associated_crop.nitrogen_stock + shrimp_organic_n_bonus;
            plot.soil_health <- min(max_soil_health, plot.soil_health + regeneration_rate);
        }
    }
}

/**
 * Rotational Harvesting & Economic Accounting Practice for Rice-Shrimp systems.
 */
species Shrimp_Rice_Harvesting_practice parent: Harvesting_practice {

    action effect(Plot plot) {
        if (plot.associated_crop != nil and plot.associated_crop.is_aquaculture) {
            // --- SHRIMP HARVEST & ECONOMIC ACCOUNTING ---
            Aqua_species sp <- plot.associated_crop.aqua_variety;

            // Convert g/m² to tons/ha (0.01 factor)
            plot.final_yield_ton_ha <- plot.associated_crop.biomass * biomass_to_ton_conv;
            plot.straw_yield_ton_ha <- 0.0;
            plot.actual_sold_yield <- plot.final_yield_ton_ha * (1.0 - aqua_harvest_loss_rate);

            // Soil regeneration after aquaculture phase
            ask plot { do update_soil_status(true); }

            // Add harvest labor (netting, draining, sorting)
            plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor_shrimp_harvest;

            // Compute seasonal operational costs
            float r_lab <- (current_date.year in the_market.r_labor.keys) ? the_market.r_labor[current_date.year] : 1.0;
            float r_wat <- (current_date.year in the_market.r_water.keys) ? the_market.r_water[current_date.year] : 1.0;
            float r_mec <- (current_date.year in the_market.r_mech.keys) ? the_market.r_mech[current_date.year] : 1.0;
            float r_fer <- (current_date.year in the_market.r_fertilizer.keys) ? the_market.r_fertilizer[current_date.year] : 1.0;

            float cost_labor <- plot.the_farmer.accumulated_labor_hours * labor_cost_per_hour * r_lab;
            float cost_post_larvae <- plot.associated_crop.seed_density_kg_ha * sp.stocking_unit_cost;
            float cost_feed <- plot.total_fertilizer_applied * aqua_feed_unit_price * r_fer;
            float cost_water <- plot.total_water_pumped * pumping_cost_per_mm * r_wat;
            float cost_meca <- plot.the_farmer.mechanization_costs * r_mec;

            plot.the_farmer.revenue <- 0.0; // Market will add shrimp sales revenue at end_of_season
            plot.the_farmer.total_costs <- cost_labor + cost_post_larvae + cost_feed + cost_water + cost_meca;
        } else {
            // --- STANDARD RICE HARVEST & ECONOMIC ACCOUNTING ---
            invoke effect(plot);
        }
    }
}

/**
 * Dual-regime Water Management Practice:
 * - During Shrimp season: Actively pumps brackish water to maintain deep pond levels (e.g., 300 mm).
 * - During Rice season: Operates as standard AWD/CF, blocking saline water (> 4 g/L).
 */
species Brackish_Rotational_Irrigating_practice parent: Irrigating_practice {
    string name <- "Brackish_Rotational_Irrigation";
    float pumping_capacity <- pumping_capacity_sust;

    float manage_water_needed(Plot plot) {
        if (plot.associated_crop = nil) { return 0.0; }

        if (plot.associated_crop.is_aquaculture) {
            float target_depth <- plot.associated_crop.aqua_variety.min_water_level + 50.0;
            return (plot.water_level < plot.associated_crop.aqua_variety.min_water_level) ? (target_depth - plot.water_level) : 0.0;
        } else {
            return (plot.water_level <= awd_pumping_threshold) ? (water_target_flooded - plot.water_level) : 0.0;
        }
    }

    action effect(Plot plot) {
        if (plot.associated_crop = nil) { return; }

        float water_needed <- max(0.0, manage_water_needed(plot));
        bool is_aqua <- plot.associated_crop.is_aquaculture;

        // Quality check: Shrimp require brackish water within their tolerance bounds; Rice requires freshwater (< 4 g/L)
        bool water_is_good_quality <- is_aqua ?
            (plot.my_cell.salinity_level >= plot.associated_crop.aqua_variety.salinity_min and plot.my_cell.salinity_level <= plot.associated_crop.aqua_variety.salinity_max) :
            (plot.my_cell.salinity_level < max_pumping_salinity);

        // Availability check: Brackish canal water is always available in the dry season for coastal/estuarine plots
        bool water_is_available <- is_aqua ? true : ((rain_last_days > min_rain_for_access) and (total_province_pumping < max_province_pumping_capacity));

        float water_pumped <- (water_is_good_quality and water_is_available) ? min(pumping_capacity, water_needed) : 0.0;

        plot.water_level <- plot.water_level + water_pumped;
        plot.associated_crop.water_pumped_today <- water_pumped;
        if (water_pumped > 0) {
            plot.total_water_pumped <- plot.total_water_pumped + water_pumped;
        }

        // Daily labor for water & dissolved oxygen monitoring
        plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + (is_aqua ? daily_labor_aqua_water : daily_labor_water_awd);

        // Drainage if extreme rainfall threatens rice submergence (only active for rice)
        if (not is_aqua and plot.water_level > flood_stress_threshold) {
            plot.water_level <- plot.water_level - pumping_capacity;
            plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + (pumping_energy_cost * pumping_cost_per_mm);
        }
    }
}



// ======================================================================
// GENERIC CROP PRACTICE DEFINITION
// ======================================================================


species Crop_strategy virtual: false {
	string id;  // Unique identifier for the practice
	string short_name; // Short name used for displays
	rgb color;  // Color used for visual representation
	Sowing_practice sowing;
	Harvesting_practice harvesting;
	Irrigating_practice irrigation;
	list<Practice> other_practices; 
	 
	map<string, Practice> practices_id;
	bool is_active_season <- false;
	
	// key indicators regrouped by seasons (eg: ["harvest"::[21.0,23.4,19.9] is the total of crop produced for seasons 1 to 3.
 
 	// is season summary used or should it be removed ?
	map<string, list<float>> seasons_summary <- map((key_indicators + (expense_categories.keys collect("Expense: "+each))) collect(each::list<float>([]))); 
	
	// year summary for the set of indicators key_indicators and expenses.
	map<string, list<float>> year_summary <- map(
		((key_indicators - ["Current season"] + (expense_categories.keys collect("Expense: "+each))) collect(each::[each="Current year"?current_date.year:0.0]))
	); 
	float practice_area <- 1.0; // total plot area dedicated to the practice. Updated at the beginning of each year (moment to decide for practices changes)
	float day_income <- 0.0; // day income. Reinitialized at 0 the first day
	float day_expenses <- 0.0; // day expense. Reinitialized at 0 the first day
	float total_balance <- 0.0;
	float balance_per_ha <- 0.0;
	
	// Economic parameters (per hectare)
	float market_price; // Market price per kilogram
	float fert_cost;  // Fertilizer cost in currency per kg
	float seed_cost;// Seed cost per ha 
	float other_cost ;// Other production costs
	
 	list<int> activity <- [];
	
	
	action initialize() {
		practices_id <- (other_practices as_map (each.name :: each)) + ([sowing.name :: sowing, harvesting.name :: harvesting]);
	} 
	 
	
	bool has_practice(string practice_id) {
		return practice_id in practices_id.keys;
	}
	Practice get_practice(string practice_id) {
		return practices_id[practice_id];
	}
	
	
		// Reset yearly key indicator monitors. 
	
	action switch_to_new_year() {
		// add monitors for the new year
		loop key over: seasons_summary.keys - ["Current year","Current season"] {
			year_summary[key] <- year_summary[key] + 0.0;
		}
		year_summary["Current year"] <+ current_date.year;
		do compute_practice_area(); 
	}
	
	//  compute crop surface and store it in the yearly indicators.
	action compute_practice_area() {
		practice_area <- plot_species where(each.the_farmer.practice = self) sum_of(each.surface_in_ha);
		year_summary["Crop area"][length(year_summary["Crop area"]) - 1] <- practice_area;
	}


	// store actual value for a given indicator to build a yearly or season summary
	action add_to_indicator(string indicator, float val){
		// Error message to help debug when the indicator is not in the list
		if !(indicator in year_summary.keys){
			write "ERROR in year summary: "+indicator+" not in "+year_summary.keys;
		}
		if !(indicator in seasons_summary.keys){
			write "ERROR in seasons summary: "+indicator+" not in "+year_summary.keys;
		}
		list<float> l <- seasons_summary[indicator];
		
		l[length(l) - 1] <- last(l) + val;
		seasons_summary[indicator] <- l;
		
		
		list<float> l2 <- year_summary[indicator];
		l2[length(l2) - 1] <- last(l2) + val;
		year_summary[indicator] <- l2;
	}
	
	
	list<string> create_x_labels(){
		list<string> tmp <- [];
		loop i from: 0 to: length(seasons_summary["Current season"] - 1){
			tmp <+ 'Y'+seasons_summary["Current year"][i]+"S"+seasons_summary["Current season"][i];
		}
		return tmp;
	}
	
}
 
 
species BAU_rice_3_season parent:Crop_strategy {
	string id <-  BAU_3S ; // Unique identifier for the practice
	string short_name <- "Business as usual - 3 seasons"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),three_seasons_sowing, false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(three_seasons_sowing) -1 {
					ftr[three_seasons_sowing.keys[i]] <-  bau_n_trigger_threshold*fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <-  bau_nitrogen_goal*fert_targets_coeff_3_seasons[i];
					pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: bau_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, pta , false, false); 
			} 
			do initialize();
	}
} 

 
species BAU_rice_3_season_AWD parent:Crop_strategy {
	string id <-  BAU_3S_AWD ; // Unique identifier for the practice
	string short_name <- "Business as usual - 3 seasons with AWD"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),three_seasons_sowing, false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_AWD_practice(myself);
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(three_seasons_sowing) -1 {
					ftr[three_seasons_sowing.keys[i]] <-  bau_n_trigger_threshold*fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <-  bau_nitrogen_goal*fert_targets_coeff_3_seasons[i];
					pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: bau_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, pta , false, false); 
			} 
			do initialize();
	}
}

species Custom_practices parent: Crop_strategy {
	string id <-  CUSTOM ; // Unique identifier for the practice
	string short_name <- "Custom practices"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),three_seasons_sowing, false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(three_seasons_sowing) -1 {
					ftr[three_seasons_sowing.keys[i]] <-  bau_n_trigger_threshold*fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <-  bau_nitrogen_goal*fert_targets_coeff_3_seasons[i];
					pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: bau_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, pta , false, false); 	
			} 
			do initialize();
		}
}


species BAU_rice_3_season_awd parent:Crop_strategy {
	string id <-  BAU_3S_AWD  ; // Unique identifier for the practice
	string short_name <- "Business as usual - but with AWD"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),three_seasons_sowing, false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_AWD_practice(myself);
				
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(three_seasons_sowing) -1 {
					ftr[three_seasons_sowing.keys[i]] <-  bau_n_trigger_threshold*fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <-  bau_nitrogen_goal*fert_targets_coeff_3_seasons[i];
					pta[three_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_3_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: bau_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);		
				
				do add_pesticide_practice(myself, pta , false, false); 	
				
			} 
			do initialize();
	}
} 

 
species BAU_rice_2_season parent:Crop_strategy {
	string id <- BAU_2S; // Unique identifier for the practice
	string short_name <- "Business as usual - 2 seasons"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),two_seasons_sowing, false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(two_seasons_sowing) -1 {
					ftr[two_seasons_sowing.keys[i]] <-  bau_n_trigger_threshold*fert_trigger_thresholds_coeff_2_seasons[i];
					fta[two_seasons_sowing.keys[i]] <-  bau_nitrogen_goal*fert_targets_coeff_2_seasons[i];
					pta[two_seasons_sowing.keys[i]] <- bau_pesticide_threshold * pesticide_thresholds_2_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: bau_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, pta , false, false); 	
				do add_fallow_practice(myself,fallow_day);
			} 
			do initialize();
	}
} 



species OMH_rice parent:Crop_strategy {
	string id <- OMRH ; // Unique identifier for the practice
	string short_name <- "One Million Hectares"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = ST25),two_seasons_sowing, true);
		 	harvesting <- world.create_harvesting_practice(true);
			ask world {
				do add_AWD_practice(myself);
				
				map<int,float> ftr;
				map<int,float> fta;
				map<int,float> pta;
				loop i from: 0 to: length(two_seasons_sowing) -1 {
					ftr[two_seasons_sowing.keys[i]] <-  sust_n_trigger_threshold*fert_trigger_thresholds_coeff_2_seasons[i];
					fta[two_seasons_sowing.keys[i]] <-  sust_nitrogen_goal*fert_targets_coeff_2_seasons[i];
					pta[two_seasons_sowing.keys[i]] <- sust_pesticide_threshold * pesticide_thresholds_2_seasons[i];
				}
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: ftr, 
					    base_dose_: sust_n_dose_amount,               
					    targets: fta, 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, pta , true, true); 	
				do add_fallow_practice(myself,fallow_day);
				
			
			} 
			do initialize();
	}
}


/**
 * Complete Strategy Definition: Rice-Shrimp Rotational System (1 Shrimp cycle + 1 High-Quality Rice cycle)
 */
species Rice_Shrimp_strategy parent: Crop_strategy {
    string id <- RICE_SHRIMP;
    string short_name <- "Rice-Shrimp Rotation (Lua-Tom)";
    rgb color <- practices_color[id];

    init {
        // Schedule: Day 35 (Feb -> Shrimp stocking, cleans straw), Day 210 (July -> Rice sowing)
        map<int, bool> rotation_days <- [35::true, 210::true];

        create Shrimp_Rice_Sowing_practice (
            type_of_cultivar: Cultivar first_with (each.name = ST25),
            target_aqua_species: Aqua_species first_with (each.name = "PENAEUS_MONODON"),
            implementation_days: rotation_days,
            mechanical_seeding: true
        ) returns: sow_p;
        sowing <- first(sow_p);

        create Shrimp_Rice_Harvesting_practice (collect_straw: true) returns: harv_p;
        harvesting <- first(harv_p);

        create Brackish_Rotational_Irrigating_practice {
            myself.irrigation <- self;
            myself.other_practices << self;
        }

        // Low nitrogen input for Rice season (thanks to shrimp organic residue) and feed input for Shrimp season
        map<int, float> ftr <- [35::10.0, 210::sust_n_trigger_threshold];
        map<int, float> fta <- [35::60.0, 210::(sust_nitrogen_goal * 0.6)]; // 40% reduction in chemical N during rice season!

        ask world {
            do add_input_use_practice(
                cp: myself,
                trigger_thresholds_: ftr,
                base_dose_: sust_n_dose_amount,
                targets: fta,
                mech: false
            );
            // Note: NO pesticide practice is added! Rice-Shrimp farmers strictly avoid pesticides
            // to prevent toxic residue accumulation in pond sediment.
        }
        do initialize();
    }
}