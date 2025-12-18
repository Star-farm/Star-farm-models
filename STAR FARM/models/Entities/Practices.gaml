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
	// Dark theme version
	//	map<string,rgb> expenses_categories <- ["Seed"::rgb(26, 188, 156),"Fertilizer"::rgb(253, 203, 110),"Irrigation"::rgb(133, 193, 233),"Manpower"::rgb(241, 148, 138),"Other"::rgb(189, 195, 199)];
	
	// Action to create all practice instances from their species definitions
	action create_practices {
		loop s over: Crop_practice.subspecies { 
			create s returns: new_practices;
			Crop_practice ct <- Crop_practice(first(new_practices));
			practices[ct.id] <- ct ;
		}
	}
	
	
		
}



// ======================================================================
// GENERIC CROP PRACTICE DEFINITION
// ======================================================================

species Crop_practice virtual: true{
	string id;  // Unique identifier for the practice
	string short_name; // Short name used for displays
	rgb color;  // Color used for visual representation
	rgb color_farmer;  // Color used for the farmer representation (UI or visualization)
	
	// key indicators regrouped by seasons (eg: ["harvest"::[21.0,23.4,19.9] is the total of crop produced for seasons 1 to 3.
 
 	// is season summary used or should it be removed ?
	map<string, list<float>> seasons_summary <- map((key_indicators + (expense_categories.keys collect("Expense: "+each))) collect(each::list<float>([]))); 
	
	map<string, list<float>> year_summary <- map(
		((key_indicators-["Current season"]+ (expense_categories.keys collect("Expense: "+each))) collect(each::[each="Current year"?1.0:0.0]))
	); 
	float practice_area <- 1.0; // total plot area dedicated to the practice. Updated at the beginning of each year (moment to decide for practices changes)
	float day_income <- 0.0;// update: 0.0; // day income. Reinitialized at 0 the first day
	float day_expenses <- 0.0;// update: 0.0; // day expense. Reinitialized at 0 the first day
	float total_balance <- 0.0;
	float balance_per_ha <- 0.0;
	

	// Economic parameters (per hectare)
	float market_price; // Market price per kilogram
	float fert_cost;  // Fertilizer cost
	float seed_cost;// Seed cost
	float other_cost ;// Other production costs
	
 
	// Crop calendar information
	list<int> sowing_date;       // List of possible sowing dates (day of year)
	list<int> harvesting_date;   // List of possible harvesting dates (day of year)
	bool is_active_season <- false;// update: (PG_model.is_sowing_date(self) or PG_model.is_harvesting_date(self))?!is_active_season:is_active_season;
	list<int> activity <- [];
	
	// Agricultural management operations
	map<int,string> irrigation;       // Irrigation type per day (e.g., continuous, AWD, none)
	map<int,float> fertilization;     // Fertilizer quantity applied per day
	
	// why is it here ? Can we make a "generic handler" to keep each model appart ?
	// Data used when interfacing with the ORYZA crop growth model
	map<list<int>,float> oryza_data;  // Yield data indexed by start and end dates
	pair<list<int>,float> current_oryza; // Current yield pair in use

	/** 
	 * Update season status. 
	 * If it is the start of a new season, create the corresponding key indicators
	 */
	 
	
	reflex active_season_update{
		 if (PG_models[id].is_sowing_date(self,1)){
		 	is_active_season <- true;
		 	// starts a new season
		 	loop key over: seasons_summary.keys-["Current year","Current season"] {
				seasons_summary[key] <- seasons_summary[key]+0.0;
			}
			// add indicators that are only updated at the first step of the season
			// add the current year
			seasons_summary["Current year"] <+ current_year;
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
		 }
		 if (PG_models[id].is_harvesting_date(self,-1)){
		 	is_active_season <- false;
		 	
//			write seasons_summary;
		 }
		 activity << int(is_active_season);
	}
	
	// Reset yearly key indicator monitors. 
	// The first day of the Problem with the scheduler if sowing is the first day ?
	reflex switch_to_new_year when: cycle > 0 and current_date.day_of_year = init_day_of_year{
		// add monitor for the new year
		loop key over: seasons_summary.keys-["Current year","Current season"] {
			year_summary[key] <- year_summary[key]+0.0;
		}
		year_summary["Current year"] <+ current_year;
	}
	
	// compute indicators that will be used for the whole year, such as crop surface.
	// computed on day 2 in order to prevent schedule errors (decisions made on day 1)
	reflex compute_first_day_indicators when: cycle > 0 and current_date.day_of_year = init_day_of_year+1{
		practice_area <- plot_species where(each.the_farmer.practice = self) sum_of(each.shape.area);
		year_summary["Crop area"][current_year - 1] <- practice_area;
	}
	
	// store actual value for a given indicator to build a yearly or season summary
	action add_to_indicator(string indicator, float val){
		// Error message to help debug when the indicator is not in the list
		if !(indicator in year_summary.keys){
			write "ERROR in year summary: "+indicator+" not in "+key_indicators;
		}
		if !(indicator in seasons_summary.keys){
			write "ERROR in seasons summary: "+indicator+" not in "+key_indicators;
		}
		
		list<float> l <- seasons_summary[indicator];
		l[length(l)-1] <- last(l) + val;
		seasons_summary[indicator] <- l;
		
		list<float> l2 <- year_summary[indicator];
		l2[current_year-1] <- last(l2) + val;
		year_summary[indicator] <- l2;
	}
	
	
	list<string> create_x_labels{
		list<string> tmp <- [];
		loop i from: 0 to: length(seasons_summary["Current season"] - 1){
			tmp <+ 'Y'+seasons_summary["Current year"][i]+"S"+seasons_summary["Current season"][i];
		}
		return tmp;
//		return list<string>(seasons_summary["Current season"]);
	}
	 
}


// ======================================================================
// CONTINUOUS FLOODING PRACTICE (RICE_CF)
// ======================================================================

species RiceCF parent: Crop_practice {
	string id <- RICE_CF;
	string short_name <- "Rice (CF)";
	rgb color <- rgb(198, 219, 239);
	rgb color_farmer <- rgb(33, 113, 181); // dark mode: rgb(102, 157, 246)
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [210,70];
	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	
	map<int,string> irrigation <- [0::CONTINUOUS, 91::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];	// date::quantity per ha ??
}


// ======================================================================
// ALTERNATE WETTING AND DRYING PRACTICE (RICE_AWD)
// ======================================================================

species RiceAWD parent: Crop_practice {
	string id <- RICE_AWD;
	string short_name <- "Rice (AWD)";
	rgb color <- rgb(199, 233, 192);
	rgb color_farmer <- rgb(67, 176, 105); // dark mode
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [70,210];
	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	// CERES parameters
	float AWD_threshold <- 0.5;   // fraction of FC triggering irrigation
    float irrigation_amount <- 40.0; // mm per event
	
	
	map<int,string> irrigation <- [0::CONTINUOUS, 21::ALTERNATE,81::CONTINUOUS, 90::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];
	
	
}