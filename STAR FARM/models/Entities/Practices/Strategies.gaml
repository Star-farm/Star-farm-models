/**
* Name: Strategy
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Strategies - Scenario4.gaml"
import "Strategies - Scenario3.gaml"
import "Strategies - Scenario2.gaml"
import "Strategies - Scenario1.gaml"
import "Practices.gaml"

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
	// Net seasonal income bonus from companion perennial crops on raised beds/bunds ($/ha/season)
	float perennial_net_income_bonus <- 0.0;
	
	
	// Scenario 4 - Commercialization & Value Chain attributes
	bool has_cooperative_contract <- false; // false = Spot market (middlemen), true = Formal cooperative off-take contract
	float quality_price_premium <- 0.0;     // e.g., 0.10 for +10% price premium on certified 1Mha / agroecological products
	float guaranteed_floor_multiplier <- 1.0; // Minimum market multiplier guaranteed by the cooperative (buffers price crashes)
	
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