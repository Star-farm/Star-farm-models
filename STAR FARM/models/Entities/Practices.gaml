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
	list<string> key_indicators <- ["Harvest","Profit","Crop area","Water consumption","Fertilizer consumption","Current year","Current season"];
	// key indicators regrouped by seasons (eg: ["harvest"::[21.0,23.4,19.9] is the total of crop produced for seasons 1 to 3.
	map<string, list<float>> seasons_summary <- map(key_indicators collect(each::list<float>([]))); 

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
			seasons_summary["Current year"] <+ ceil(cycle/365);
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
			seasons_summary["Crop area"] <+ Plot where (each.the_farmer.practice = self) sum_of(each.shape.area); 
		 }
		 if (PG_models[id].is_harvesting_date(self,-1)){
		 	is_active_season <- false;
		 	
			write seasons_summary;
		 }
		 activity << int(is_active_season);
	}
	
	action add_to_indicator(string indicator, float val){
		list<float> l <- seasons_summary[indicator];
		l[length(l)-1] <- last(l) + val;
		seasons_summary[indicator] <- l;
	}
	
	
	list<string> create_x_labels{
		list<string> tmp <- [];
		loop i from: 0 to: length(seasons_summary["Current season"]-1){
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
	string short_name <- "Rice (C.F.)";
	rgb color <- rgb(198, 219, 239);
	rgb color_farmer <- rgb(33, 113, 181); // dark mode: rgb(102, 157, 246)
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [210,70];
	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	
	map<int,string> irrigation <- [0::CONTINUOUS, 91::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];	
}


// ======================================================================
// ALTERNATE WETTING AND DRYING PRACTICE (RICE_AWD)
// ======================================================================

species RiceAWD parent: Crop_practice {
	string id <- RICE_AWD;
	string short_name <- "Rice (Alt. W. and D.)";
	rgb color <- rgb(199, 233, 192);
	rgb color_farmer <- rgb(67, 176, 105); // dark mode
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [70,210];
	
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	
	map<int,string> irrigation <- [0::CONTINUOUS, 21::ALTERNATE,81::CONTINUOUS, 90::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];
	
	
}