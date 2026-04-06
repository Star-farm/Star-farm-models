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
		
	// Action to create all practice instances from their species definitions
	action create_practices() {
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
		
    	float dry_yield <- plot.associated_crop.biomass * plot.associated_crop.variety.harvest_index_potential;
	  
	  	// Applying the Soil Fatigue Factor ---
        dry_yield <- dry_yield * plot.soil_health;
       
        // Update soil status: "False" because we just harvested a crop (it was not fallow)
        ask plot { do update_soil_status(false); }
        
        plot.final_yield_ton_ha <- (dry_yield * biomass_to_ton_conv) / harvest_moisture_adjust;
        plot.straw_yield_ton_ha <- (plot.associated_crop.biomass * biomass_to_ton_conv) -  plot.final_yield_ton_ha; 
 
 		float actual_sold_yield <- plot.final_yield_ton_ha * (1.0 - harvest_loss_rate);

		float rice_rev <- (actual_sold_yield * 1000) * plot.associated_crop.variety.rice_market_price * the_market.r_for_crop(plot.associated_crop.variety);
        float straw_rev <- 0.0;  
        
        if (collect_straw) { straw_rev <- (plot.straw_yield_ton_ha * 1000) * straw_market_price * the_market.r_straw[current_date.year] ; }
        
        else { 
   			// Calculate emissions generated by open burning and add to the plot's carbon footprint 
    		plot.methane_emissions_kg_ha <- plot.methane_emissions_kg_ha +  plot.straw_yield_ton_ha * straw_burn_emission_factor;
		}
        
        plot.the_farmer.revenue <- rice_rev + straw_rev;
         
        float cost_labor <- plot.the_farmer.accumulated_labor_hours * labor_cost_per_hour; 
        float cost_fert <- plot.total_fertilizer_applied * fertilizer_unit_price * the_market.r_fertilizer[current_date.year];
        float cost_pest <- plot.pesticide_count * pesticide_unit_cost * the_market.r_pesticides[current_date.year];
        float cost_water <- plot.total_water_pumped * pumping_cost_per_mm * the_market.r_water[current_date.year]; 
        float cost_seed <- plot.associated_crop.seed_density_kg_ha * plot.associated_crop.variety.seed_unit_cost * the_market.r_for_seed(plot.associated_crop.variety); 
        float cost_meca <- plot.the_farmer.mechanization_costs * the_market.r_mech[current_date.year];  
    	plot.the_farmer.total_costs <- cost_labor+ cost_fert + cost_pest + cost_water + cost_seed + cost_meca ;
        
        plot.the_farmer.profit_net <- plot.the_farmer.revenue - plot.the_farmer.total_costs;
		
       plot.the_farmer.yearly_profit <- plot.the_farmer.yearly_profit + plot.the_farmer.profit_net;
		
		
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
// GENERIC CROP PRACTICE DEFINITION
// ======================================================================


species Crop_strategy virtual: true {
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
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),[320::true,95::false, 215::false], false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_:[320::bau_n_trigger_threshold*1.0,95::bau_n_trigger_threshold*1.0,215::bau_n_trigger_threshold*0.8 ] , 
					    base_dose_: bau_n_dose_amount,               
					    targets: [320::bau_nitrogen_goal*1.3,95::bau_nitrogen_goal*1.2,215::bau_nitrogen_goal*0.8 ], 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, [320::bau_pesticide_threshold*0.4,95::bau_pesticide_threshold*1.0,215::bau_pesticide_threshold*1.6 ] , false, false); 
			} 
			do initialize();
	}
} 

species BAU_rice_3_season_sust parent:Crop_strategy {
	string id <-  BAU_3S_sust  ; // Unique identifier for the practice
	string short_name <- "Business as usual - but with AWD and sustainable inputs"; // Short name used for displays
	rgb color <- practices_color[id];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),[320::true,95::false, 215::false], false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_AWD_practice(myself);
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_:[320::sust_n_trigger_threshold*1.0,95::sust_n_trigger_threshold*1.0,215::sust_n_trigger_threshold*0.8 ] , 
					    base_dose_: sust_n_dose_amount,               
					    targets: [320::sust_nitrogen_goal*1.3,95::sust_nitrogen_goal*1.2,215::sust_nitrogen_goal*0.8 ], 
					    mech: false
					);			
				
				do add_pesticide_practice(myself, [320::sust_pesticide_threshold*0.4,95::sust_pesticide_threshold*1.0,215::sust_pesticide_threshold*1.6 ] , false, true); 
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
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = OM5451),[305::true, 115::false], false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				do add_input_use_practice(cp: myself, 
					    trigger_thresholds_: [305::bau_n_trigger_threshold*0.8,115::bau_n_trigger_threshold*1.0], 
					    base_dose_: bau_n_dose_amount,               
					    targets: [305::bau_nitrogen_goal*1.2,115::bau_nitrogen_goal*1.0], 
					    mech: false
					);			
				do add_pesticide_practice(myself, [305::bau_pesticide_threshold*0.4,115::bau_pesticide_threshold*1.0], false, false); 
				do add_fallow_practice(myself,290);
				
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
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = ST25),[305::true, 115::false], true);
		 	harvesting <- world.create_harvesting_practice(true);
			ask world {
				do add_AWD_practice(myself);
				do add_input_use_practice(cp:myself, 
				    trigger_thresholds_:[305::sust_n_trigger_threshold*0.8,115::sust_n_trigger_threshold*1.0] , 
				    base_dose_: sust_n_dose_amount,            
				    targets: [305::sust_nitrogen_goal*1.2,115::sust_nitrogen_goal*1.0], 
				    mech: true);
				do add_pesticide_practice(myself,[305::sust_pesticide_threshold*0.4,115::sust_pesticide_threshold*1.0], true, true);
				do add_fallow_practice(myself,290); 
			} 
			do initialize();
	}
}