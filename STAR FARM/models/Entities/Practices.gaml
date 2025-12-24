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
	
	
	Sowing_practice create_sowing_practice(Cultivar cultivar, list<int> days) {
		create Sowing_practice with:(type_of_cultivar: cultivar, implementation_days: days) returns: sow_pract;
		return first(sow_pract);
	}
	
	Harvesting_practice create_harvesting_practice( list<int> days) {
		create Harvesting_practice with:(implementation_days: days) returns: har_pract;
		return first(har_pract);
	}	
	
	action add_AWD_practice(Crop_practice pract, list<int> days) {
		create AWD_Irrigating_practice {
			pract.other_practices << self;
		}
	}
	
	action add_CF_practice(Crop_practice pract, list<int> days) {
		create CF_Irrigating_practice {
			pract.other_practices << self;
		}
	}
	
	
	action add_input_use_practice(Crop_practice pract, map<int, float> quantity) {
		create Input_use_practice with:(quantity::quantity){
			pract.other_practices << self;
			
		}
	}
	
	action add_pesticide_practice(Crop_practice pract, map<int, float> quantity) {
		create Pesticide_application_practice with:(quantity::quantity){
			pract.other_practices << self;
			
		} 
	}
	
}


species Practice virtual: true {
	list<int> implementation_days ;
	
	bool to_apply(int current_day) {
		return current_day in implementation_days;
	}
	
	action effect(Plot plot) virtual: true; 
} 

species Sowing_practice parent:Practice {
	string name <- "sowing";
	Cultivar type_of_cultivar;
	
	action effect(Plot plot) {
		create Crop with:(the_farmer:plot.the_farmer) {
			plot.associated_crop <- self;
			concerned_plot <- plot;
 
			crop_duration <- PG_models[plot.the_farmer.practice.id].compute_crop_duration(self);
 
		} 
		ask plot.the_farmer{do add_expenses(plot.associated_crop.sowing_cost_computation(),"Seed");}
		
		
	}
}

species Harvesting_practice parent:Practice {
	string name <- "harvesting";	
	action effect(Plot plot) {
		ask plot.the_farmer{do add_income(plot.associated_crop.harvest_income_computation());}

		ask plot.associated_crop { 
			do die; 
		}  
		plot.associated_crop <- nil;
	}
}

species Irrigating_practice parent: Practice virtual: true{
	action effect(Plot plot) {
		
	}
}


species no_Irrigating_practice parent: Practice{
	action effect(Plot plot) ;
}

species CF_Irrigating_practice parent: Practice{
	string name <- CF;
	
	action effect(Plot plot) ;
}

species AWD_Irrigating_practice parent: Practice{
	string name <- AWD;


	// CERES parameters
	float AWD_threshold <- 0.5;   // fraction of FC triggering irrigation
    float irrigation_amount <- 40.0; // mm per event
	
		
	action effect(Plot plot) ;
}

species Practice_with_quantity parent: Practice virtual: true {
	map<int,float> quantity;
	init {
		implementation_days <- quantity.keys; 
	}
	action effect(Plot plot) virtual: true;
}

species Input_use_practice parent:Practice_with_quantity {
	string name <- INPUT;
	
	
	action effect(Plot plot) {
		
		float quantity_per_ha <- quantity[plot.associated_crop.lifespan];
		float cost <- plot.associated_crop.fertilization_cost_computation(quantity_per_ha, plot.surface_in_ha); 
		ask plot.the_farmer {do add_expenses(cost,"Fertilizer");}
		ask plot.the_farmer.practice {do add_to_indicator("Fertilizer consumption", quantity_per_ha * plot.surface_in_ha);}

		plot.N_avail <- plot.N_avail + quantity_per_ha * 0.1; // quantity, expressed as g/m²
	}  
}

species Pesticide_application_practice parent:Practice_with_quantity {
	string name <- PESTICIDE;

	
	action effect(Plot plot) {
		
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
 
 
species BAU_rice parent:Crop_practice {
	string id <- BAU ; // Unique identifier for the practice
	string short_name <- "Business as usual"; // Short name used for displays
	rgb color <- practices_color[short_name];  // Color used for visual representation	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	list<Practice> other_practices;
	
	init {
		 	sowing <- world.create_sowing_practice(first(Cultivar),[120, 300]);
		 	harvesting <- world.create_harvesting_practice([210,70]);
			other_practices << world.add_CF_practice(self, [1]);
			ask world {
				do add_input_use_practice(myself, [7::40.0, 20::40.0, 50::40.0]);
				do add_pesticide_practice(myself, [7::40.0, 20::40.0, 50::40.0]); 
			} 
	}
}



species AWD_rice parent:Crop_practice {
	string id <- AWD ; // Unique identifier for the practice
	string short_name <- "AWD"; // Short name used for displays
	rgb color <- practices_color[short_name];  // Color used for visual representation	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	list<Practice> other_practices;
	
	init {
		 	sowing <- world.create_sowing_practice(first(Cultivar),[120, 300]);
		 	harvesting <- world.create_harvesting_practice([210,70]);
			other_practices << world.add_AWD_practice(self, [1]);
			ask world {
				do add_input_use_practice(myself, [7::40.0, 20::40.0, 50::40.0]);
				do add_pesticide_practice(myself, [7::40.0, 20::40.0, 50::40.0]); 
			} 
	}
}