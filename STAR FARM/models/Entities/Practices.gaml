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

import "../Global.gaml" 

import "../Constants.gaml" 
 
// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================


 
global {
	// Map storing all crop practices available in the model, keyed by their ID
	map<string,Crop_practice> practices;
	
	// List of the indicators to be monitored
	list<string> key_indicators <- ["Harvest","Profit","Crop area","Water consumption","Fertilizer consumption","Current year","Current season"];
	// List of the expense categories, and the corresponding color for display
	map<string,rgb> expense_categories <- ["Seed"::rgb(22, 160, 133),"Fertilizer"::rgb(241, 196, 15),"Irrigation"::rgb(52, 152, 219),"Manpower"::rgb(230, 126, 34),"Other"::rgb(127, 140, 141)];
		
	// Action to create all practice instances from their species definitions
	action create_practices {
		loop s over: Crop_practice.subspecies { 
			create s returns: new_practices;
			Crop_practice ct <- Crop_practice(first(new_practices));
			practices[ct.id] <- ct ;
		}
		ask Crop_practice {
			do initialize;
		}
	}
	
	
	Sowing_practice create_sowing_practice(Cultivar cultivar, list<int> days, bool mechanical) {
		create Sowing_practice with:(type_of_cultivar: cultivar, implementation_days: days,  mechanical_seeding:mechanical) returns: sow_pract;
		return first(sow_pract);
	}
	
	Harvesting_practice create_harvesting_practice (bool collect_straw){
		create Harvesting_practice with:(collect_straw:collect_straw) returns: har_pract;
		return first(har_pract);
	}	
	
	action add_AWD_practice(Crop_practice pract) {
		create AWD_Irrigating_practice  {
			pract.irrigation <- self;
			pract.other_practices << self;
		}
	}
	
	action add_fallow_practice(Crop_practice pract, int doy_end) {
		create Fallow  {
			day_end_fallow <- doy_end;
			pract.other_practices << self;	
		} 
	}
	
	action add_CF_practice(Crop_practice pract) {
		create CF_Irrigating_practice  {
			pract.irrigation <- self;
			pract.other_practices << self;
		} 
	}
	
	
	action add_input_use_practice(Crop_practice pract, float target_nitrogen, bool mec) {
		create Input_use_practice with:(target_nitrogen:target_nitrogen, mechanical:mec){
			pract.other_practices << self;
		}
	}
	
	action add_pesticide_practice(Crop_practice pract, float pesticide_threshold, bool mec) {
		create Pesticide_application_practice with:(pesticide_threshold:pesticide_threshold, mechanical:mec){
			pract.other_practices << self;
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

species Fallow parent: Practice {
	
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
	list<int> implementation_days ;
	string name <- "sowing";
	Cultivar type_of_cultivar;
	bool mechanical_seeding;
	float labor <- mechanical_seeding ? labor_sowing_machine_hours : labor_sowing_manual_hours;
			
	
	bool to_apply(Plot plot, int current_day) { 
		return current_day in implementation_days; 
	} 
	
	
	action effect(Plot plot) {
		create Crop with:(the_farmer:plot.the_farmer, variety:type_of_cultivar  ) {
			seed_density_kg_ha <- myself.mechanical_seeding ? seed_density_kg_ha_mechanical : seed_density_kg_ha_broadcast;
			plot.associated_crop <- self;
			concerned_plot <- plot; 
			
			thermal_units_total <- variety.tt_emergence + variety.tt_veg + variety.tt_rep + variety.grain_filling_duration;
       		potential_rue_calibrated <- RUE * rue_efficiency_factor; 
        	salt_threshold_val <- variety.salinity_tolerance;
 			
 			concerned_plot.stress_days_salinity <- 0;
    		concerned_plot.stress_days_drought <- 0;
    		concerned_plot.stress_days_flood <- 0; 
    		concerned_plot.stress_days_flood_continuous <- 0; 
    		concerned_plot.pesticide_count <- 0;
    		concerned_plot.max_stress_days_flood_continuous <- 0;  
    		concerned_plot.total_water_pumped <- 0.0;  
    		concerned_plot.methane_emissions_kg_ha <- 0.0;
    		concerned_plot.final_yield_ton_ha <- 0.0;
    		concerned_plot.straw_yield_ton_ha <- 0.0;
    		the_farmer.accumulated_labor_hours <- 0.0;
    		the_farmer.mechanization_costs <- (myself.mechanical_seeding ? mech_cost_sust_fixed : mech_cost_bau_fixed);
			

    
   		}  
   		
	}
}



species Harvesting_practice parent:Practice {
	string name <- "harvesting";
	float labor <- labor_harvest_supervision;
		
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
 
        float rice_rev <- (plot.final_yield_ton_ha * 1000) * plot.associated_crop.variety.rice_market_price;
        float straw_rev <- 0.0; 
        
        if (collect_straw) { straw_rev <- (plot.straw_yield_ton_ha * 1000) * straw_market_price; }
        
        plot.the_farmer.revenue <- rice_rev + straw_rev;
         
        float cost_fert <- plot.associated_crop.total_fertilizer_applied * fertilizer_unit_price;
        float cost_pest <- plot.pesticide_count * pesticide_unit_cost;
        float cost_water <- plot.total_water_pumped * pumping_cost_per_mm;
        float cost_seed <- plot.associated_crop.seed_density_kg_ha * plot.associated_crop.variety.seed_unit_cost; 
        float cost_meca <- plot.the_farmer.mechanization_costs; 
    
        plot.the_farmer.total_costs <- cost_fert + cost_pest + cost_water + cost_seed  + cost_meca;
        
        plot.the_farmer.profit_net <- plot.the_farmer.revenue - plot.the_farmer.total_costs;
		
       plot.the_farmer.yearly_profit <- plot.the_farmer.yearly_profit + plot.the_farmer.profit_net;
		
		
		ask plot.associated_crop { 
			do die; 
		}  
		plot.associated_crop <- nil;
	}
}

species Irrigating_practice parent: Practice virtual: true{
	
	float manage_water_needed(Plot plot)  virtual: true;
	float pumping_capacity;
	float pumping_energy_cost;
	bool to_apply(Plot plot, int current_day) {
		return plot.associated_crop != nil;
	}
	
	action effect(Plot plot) {
		 
		 plot.associated_crop.water_level <- plot.associated_crop.water_level + the_weather.rain - daily_water_loss_mm;
       
        if (plot.associated_crop.water_level <= 0) {  
        	plot.methane_emissions_kg_ha <- plot.methane_emissions_kg_ha + (methane_base_emission * ch4_reduction_factor);
        } 
        else { 
        	plot.methane_emissions_kg_ha <- plot.methane_emissions_kg_ha + methane_base_emission;
        }
        float water_needed <- max(0,manage_water_needed(plot));
       
        bool water_is_good_quality <- plot.my_cell.salinity_level < max_pumping_salinity;
        bool water_is_available <- (rain_last_days > min_rain_for_access) and (total_province_pumping < max_province_pumping_capacity);
      
        float water_pumped <- (water_is_good_quality and water_is_available) ? water_needed: 0.0;
       
 		plot.associated_crop.water_level <- plot.associated_crop.water_level + water_pumped;
       
        plot.associated_crop.water_pumped_today <-  water_pumped; 
        if (water_pumped > 0) {  
        	plot.total_water_pumped <- plot.total_water_pumped + water_pumped;
        }
        
      	if (plot.associated_crop.water_level > flood_stress_threshold) {
        	plot.associated_crop.water_level <- plot.associated_crop.water_level - pumping_capacity;
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
		
		if (plot.associated_crop.water_level < water_target_flooded) { 
			water_needed <- water_target_flooded - plot.associated_crop.water_level; 
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
		if (plot.associated_crop.water_level <= awd_pumping_threshold) {
			water_needed <- water_target_flooded - plot.associated_crop.water_level; 
		}
        return water_needed;
	}
}

species Pesticide_application_practice parent:Practice {
	string name <- PESTICIDE;
	int days_since_last_spray; 
	float pesticide_threshold;
	bool mechanical;
	float labor <- mechanical ? labor_spray_drone_hours : labor_spray_manual_hours;
	
	bool to_apply(Plot plot, int current_day) {
		if (plot.associated_crop = nil) {
			return false;
		}
		days_since_last_spray <- days_since_last_spray + 1;
    	return plot.pest_load > pesticide_threshold and days_since_last_spray >= pest_spray_cooldown_days;
	}
	action effect(Plot plot) {
		days_since_last_spray <-0;
		plot.pest_load <- 0.0;  
        plot.my_cell.pollution_level <- plot.my_cell.pollution_level + pesticide_pollution_add;
       	plot.pesticide_count <- plot.pesticide_count + 1; 
    	if (mechanical) {
        	plot.the_farmer.mechanization_costs <- plot.the_farmer.mechanization_costs + cost_service_drone_spray;
        }
        plot.the_farmer.accumulated_labor_hours <- plot.the_farmer.accumulated_labor_hours + labor;
	}  
}
species Input_use_practice parent:Practice {
	string name <- INPUT;
	float target_nitrogen;
	bool mechanical;
	float labor <- mechanical ? labor_fertilizer_machine_hours : labor_fertilizer_manual_hours;
	
	bool to_apply(Plot plot, int current_day) {
		
		return plot.associated_crop != nil and plot.associated_crop.nitrogen_stock < n_stock_low_threshold and plot.associated_crop.total_fertilizer_applied < target_nitrogen and plot.associated_crop.growth_stage < n_late_stage_limit;
	}
	
	action effect(Plot plot) {
		
		// 1. Calculate the degradation gap (e.g., 1.0 - 0.8 = 0.2)
        float degradation_gap <- 1.0 - plot.soil_health;
        
        // 2. Define a compensatory factor (Simple linear compensation)
        // If soil is perfect (1.0), factor is 1.0. 
        // If soil is degraded (0.8), factor becomes 1.2 (+20% fertilizer)
        float compensatory_factor <- 1.0 + degradation_gap;
        
        // 3. Calculate the actual amount needed
        float amount <- n_application_dose * compensatory_factor; 
        
        // 4. Apply to the crop (The crop receives the nitrogen)
        plot.associated_crop.nitrogen_stock <- plot.associated_crop.nitrogen_stock + amount;
        plot.associated_crop.total_fertilizer_applied <- plot.associated_crop.total_fertilizer_applied + amount;

	} 
} 



// ======================================================================
// GENERIC CROP PRACTICE DEFINITION
// ======================================================================


species Crop_practice virtual: true {
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
	
	
	action initialize {
		practices_id <- (other_practices as_map (each.name :: each)) + ([sowing.name :: sowing, harvesting.name :: harvesting]);
	} 
	 
	
	bool has_practice(string practice_id) {
		return practice_id in practices_id.keys;
	}
	Practice get_practice(string practice_id) {
		return practices_id[practice_id];
	}
	
	
		// Reset yearly key indicator monitors. 
	
	action switch_to_new_year {
		// add monitors for the new year
		loop key over: seasons_summary.keys - ["Current year","Current season"] {
			year_summary[key] <- year_summary[key] + 0.0;
		}
		year_summary["Current year"] <+ current_date.year;
		do compute_practice_area; 
	}
	
	//  compute crop surface and store it in the yearly indicators.
	action compute_practice_area{
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
	
	
	list<string> create_x_labels{
		list<string> tmp <- [];
		loop i from: 0 to: length(seasons_summary["Current season"] - 1){
			tmp <+ 'Y'+seasons_summary["Current year"][i]+"S"+seasons_summary["Current season"][i];
		}
		return tmp;
	}
	
	
	action sowing_season_update{
		if (not is_active_season){
			is_active_season <- true;
		 	// starts a new season
		 	loop key over: seasons_summary.keys-["Current year","Current season"] {
				seasons_summary[key] <- seasons_summary[key]+0.0;
			}
			// add indicators that are only updated at the first step of the season
			// add the current year
			seasons_summary["Current year"] <+ current_date.year;
			//add the season number (reset at the beginning of the year)
			float new_season_index;
			int len <- length(seasons_summary["Current year"]);
			if (len = 1 or last(seasons_summary["Current year"]) != seasons_summary["Current year"][len-2]){
				new_season_index <- 1.0;
			}else{
				new_season_index <- last(seasons_summary["Current season"])+1;
			}
			seasons_summary["Current season"] <+ new_season_index;
			// add the crop area data
			seasons_summary["Crop area"] <+ plot_species where (each.the_farmer.practice = self) sum_of(each.shape.area); 
		 
		 	activity << int(is_active_season);
		 }
	}
	
	action harvesting_season_update{
		if is_active_season {
			is_active_season <- false;
		 	activity << int(is_active_season);
		}
		
	}
	
	

	
}
 
 
species BAU_rice_3_season parent:Crop_practice {
	string id <-  "BAU-3seasons"  ; // Unique identifier for the practice
	string short_name <- "Business as usual - 3 seasons"; // Short name used for displays
	rgb color <- practices_color[short_name];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM5451"),[320,95, 215], false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				do add_input_use_practice(myself, bau_nitrogen_goal, false);
				do add_pesticide_practice(myself, bau_pesticide_threshold, false); 
			} 
	}
} 

 
species BAU_rice_2_season parent:Crop_practice {
	string id <- "BAU-2seasons" ; // Unique identifier for the practice
	string short_name <- "Business as usual - 2 seasons"; // Short name used for displays
	rgb color <- practices_color[short_name];  // Color used for visual representation	

	list<Practice> other_practices;
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM5451"),[305, 115], false);
		 	harvesting <- world.create_harvesting_practice(false);
			ask world {
				do add_CF_practice(myself);
				do add_input_use_practice(myself, bau_nitrogen_goal, false);
				do add_pesticide_practice(myself, bau_pesticide_threshold, false); 
				do add_fallow_practice(myself,290);
			} 
	}
} 



species OMH_rice parent:Crop_practice {
	string id <- OMRH ; // Unique identifier for the practice
	string short_name <- "One Million Hectares"; // Short name used for displays
	rgb color <- practices_color[short_name];  // Color used for visual representation	

	list<Practice> other_practices;
	
	init {
		 	sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "ST25"),[305, 115], true);
		 	harvesting <- world.create_harvesting_practice(true);
			ask world {
				do add_AWD_practice(myself);
				do add_input_use_practice(myself, sust_nitrogen_goal, true);
				do add_pesticide_practice(myself,sust_pesticide_threshold, true);
				do add_fallow_practice(myself,290); 
			} 
	}
}