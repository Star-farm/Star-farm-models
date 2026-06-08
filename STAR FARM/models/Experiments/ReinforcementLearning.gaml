/**
* Name: ReinforcementLearning
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model ReinforcementLearning


import "Generic Experiment.experiment"  


global {
	
	
	int start_year <- 2025;
    int end_year <- 2050;
    string OPTIMISTIC <- "Optimistic" ; 
    string BASELINE <- "Baseline" ;
    string PESSIMISTIC <- "Pessimistic";
     
    string STANDARD <- "Standard";
    string RESOURCE_CRISIS <- "Crisis"; 
     
      
	string weather_scenario <- PESSIMISTIC among: [OPTIMISTIC, PESSIMISTIC]   ;
	string market_scenario <- RESOURCE_CRISIS among: [STANDARD, RESOURCE_CRISIS]   ;
	
	action init_action() {
		switch weather_scenario {
			match OPTIMISTIC {
				do generate_scenario(OPTIMISTIC,start_year, end_year, 0.5, 1.0, 1.2, 0.0,0,0);
			}
			match BASELINE {
				do generate_scenario(BASELINE,start_year, end_year,1.2, 2.5, 1.4, 0.03,15,10);
			}
			match PESSIMISTIC{
				do generate_scenario(PESSIMISTIC,start_year, end_year, 2.5, 4.5, 1.6, 0.06,30,20);
			}
		} 
		
		switch market_scenario {
			match STANDARD {
				create Market { 
           			market_id <- "Standard";
            		// Setup: We leave specific trends at 0.0 (neutral)
            		// We set high correlation (0.8) with the global economy
            		corr_water <- 0.8; trend_water <- 0.0;
            		corr_fertilizer <- 0.9; trend_fertilizer <- 0.0; // Follows oil/gas prices
            		the_market <- self;
        		}
			}
			match RESOURCE_CRISIS {
				create Market {
           			market_id <- "Resource-Crisis";
           			
		            // WATER: Becomes expensive (+5% per year ON TOP of inflation) and uncorrelated (0.2)
		            corr_water <- 0.2; 
		            trend_water <- 0.05; 
		            volatility_water <- 0.15; // Very unstable (random droughts)
		
		            // FERTILIZERS: Carbon taxes or shortages (+4% per year)
		            corr_fertilizer <- 0.5;
		            trend_fertilizer <- 0.04;
		
		            // MECHANIZATION: Becomes cheaper (technical progress / efficiency)
		            corr_mech <- 0.5;
		            trend_mech <- -0.01;
		            
		            the_market <- self;
        		}
			}
		}
		ask the_market {
			do generate_data(start_year,end_year);
		}	
	}
	
		


	action change_irrigation(Farmer f, bool to_awd) {
		ask f {
			string pract <- practice.irrigation.name;
			if (pract = CF) and to_awd{
				ask practice.irrigation {do die();} 
				ask myself {
					do add_AWD_practice(myself.practice);	
				}	
			} else if (pract != CF) and  not to_awd{
				ask practice.irrigation {do die();} 
				ask myself {
					do add_CF_practice(myself.practice);	
				}
			}	
		}			
	}
	
	// ----------------------------------------------------------------------
	// ACTION : PESTICIDE MANAGEMENT CHANGE (BAU vs IPM)
	// ----------------------------------------------------------------------
	action change_pesticide_management(Farmer f, bool use_IPM) {
		ask f {
			// 1. Find and remove the old pesticide practice
			list<Pesticide_application_practice> pp <- practice.other_practices of_species Pesticide_application_practice;
			practice.other_practices <- practice.other_practices - pp;
			ask pp { do die(); }
			
			// 2. Define the new thresholds based on the global variables
			map<int,float> pta;
			bool is_three_seasons <- length(practice.sowing.implementation_days) = 3;
			
			float base_pest_threshold <- use_IPM ? sust_pesticide_threshold : bau_pesticide_threshold;
			
			if (is_three_seasons) {
				loop i from: 0 to: length(three_seasons_sowing) - 1 {
					pta[three_seasons_sowing.keys[i]] <- base_pest_threshold * pesticide_thresholds_3_seasons[i];
				}
			} else {
				loop i from: 0 to: length(two_seasons_sowing) - 1 {
					pta[two_seasons_sowing.keys[i]] <- base_pest_threshold * pesticide_thresholds_2_seasons[i];
				}
			}
			
			// Apply the new practice
			ask world { do add_pesticide_practice(myself.practice, pta, use_IPM, use_IPM); }
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : INPUT/FERTILIZER USAGE CHANGE (BAU vs Sustainable)
	// ----------------------------------------------------------------------
	action change_input_usage(Farmer f, bool use_sustainable) {
		ask f {
			// 1. Find and remove the old input practice
			list<Input_use_practice> ip <- practice.other_practices of_species Input_use_practice;
			practice.other_practices <- practice.other_practices - ip;
			ask ip { do die(); }
			
			map<int,float> ftr;
			map<int,float> fta;
			bool is_three_seasons <- length(practice.sowing.implementation_days) = 3;
			
			float base_trigger <- use_sustainable ? sust_n_trigger_threshold : bau_n_trigger_threshold;
			float base_target <- use_sustainable ? sust_nitrogen_goal : bau_nitrogen_goal;
			float dose_amount <- use_sustainable ? sust_n_dose_amount : bau_n_dose_amount;
			
			if (is_three_seasons) {
				loop i from: 0 to: length(three_seasons_sowing) - 1 {
					ftr[three_seasons_sowing.keys[i]] <- base_trigger * fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <- base_target * fert_targets_coeff_3_seasons[i];
				}
			} else {
				loop i from: 0 to: length(two_seasons_sowing) - 1 {
					ftr[two_seasons_sowing.keys[i]] <- base_trigger * fert_trigger_thresholds_coeff_2_seasons[i];
					fta[two_seasons_sowing.keys[i]] <- base_target * fert_targets_coeff_2_seasons[i];
				}
			}
			
			ask world { do add_input_use_practice(myself.practice, ftr, dose_amount, fta, use_sustainable); }
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : RICE CULTIVAR CHANGE (Premium/ST25 vs Standard/OM5451)
	// ----------------------------------------------------------------------
	action change_rice_cultivar(Farmer f, bool is_premium) {
		ask f {
			if (is_premium and (practice.sowing.type_of_cultivar.name != ST25) ){
				practice.sowing.type_of_cultivar <- Cultivar first_with (each.name = ST25);
				practice.sowing.mechanical_seeding <- true; 
				practice.sowing.labor <- labor_sowing_machine_hours + labor_land_prep_hours_meca;
			} else if (not is_premium and (practice.sowing.type_of_cultivar.name = ST25) ){
				practice.sowing.type_of_cultivar <- Cultivar first_with (each.name = OM5451);
				practice.sowing.mechanical_seeding <- false;
				practice.sowing.labor <- labor_sowing_manual_hours + labor_land_prep_hours_manual;
			}
		}
	}
	
	// ----------------------------------------------------------------------
	// ACTION : CALENDAR / SEASONS CHANGE
	// ----------------------------------------------------------------------
	action change_number_seasons (Farmer f, bool three_seasons) {
		
		// 1. Memorize current pesticide and input states
		bool is_sust_input <- false;
		bool is_ipm_pest <- false;
		
		ask f.practice {
			list<Input_use_practice> ip <- other_practices of_species Input_use_practice;
			if not empty(ip) { is_sust_input <- first(ip).base_dose = sust_n_dose_amount; }
			
			list<Pesticide_application_practice> pp <- other_practices of_species Pesticide_application_practice;
			if not empty(pp) { is_ipm_pest <- first(pp).mechanical; }
			
			// 2. Change the calendar and fallow practice
			if length(sowing.implementation_days) = 2 and three_seasons{
				sowing.implementation_days <- three_seasons_sowing;
				list<Fallow_practice> fp <- other_practices of_species Fallow_practice;
				other_practices <- other_practices - fp;
				ask fp { do die(); }
		 	} else if length(sowing.implementation_days) = 3 and not three_seasons{
				sowing.implementation_days <- two_seasons_sowing;
				ask world { do add_fallow_practice(myself, fallow_day); }
		 	}	
		}
		
		// 3. Force update of related practices so their maps align with the new calendar
		do change_input_usage(f, is_sust_input);
		do change_pesticide_management(f, is_ipm_pest);
	}
	
	
	float area_premium_rice_rate() {
		
		list<Farmer> farmer_premium <- Farmer where (each.practice.sowing.type_of_cultivar.name = ST25);
		if (empty(farmer_premium)) {
			return 0.0;
		}
		
		return (farmer_premium accumulate (each.my_farm.plots)) sum_of (each.shape.area) / sum(Plot collect each.shape.area);
		
	}
	
	action define_farmer_pratices() {
		ask Farmer {
			//possible observations (in addition to the current used ones)
			write string(current_date) + " -> "+ name +" - " +
			sample(world.area_premium_rice_rate()) + ", " +
			sample(my_farm.plots mean_of (each.my_cell.pollution_level))+ ", " +
			sample(my_farm.plots mean_of (each.my_cell.salinity_level))
			
			;	 
			if flip(0.5) {
				string pract <- practice.irrigation.name;
				practice.other_practices >> pract;
				ask practice.irrigation {
					do die();
				}
				if (pract = CF) {
					ask myself {
						do add_AWD_practice(myself.practice);	
					}	
				} else {
					ask myself {
						do add_CF_practice(myself.practice);	
					}	
				}
			}
		}
	}
	 
	 action init_market() {
		if (the_market = nil) {
			create Market {
				the_market <- self; 
				ask Cultivar where (each.name = ST25) {
					myself.floor_price_cultivar <- Cultivar first_with (each.name = OM5451);
					myself.market_saturation_threshold[self] <- 900000;
					myself.price_sensitivity_k[self] <- 1.5;
				} 
			}	
		}
	}
	
	
}

experiment ReinforcementLearning title: "Reinforcement Learning" type:gui parent: generic_exp {	

	action _init_() {
		
		day_start_of_year <- 300;
		starting_date <- date([2025,1,1]) add_days (day_start_of_year -1);
		use_weather_generator <- true;	
		use_dynamic_market <- true;
		create AbstractStarFarm_model (simple_spatial_data:true, custom_practices: true, add_market_retroaction: true);
	}
	
	output {		
		layout horizontal([vertical([3::5000,1::5000])::5000,vertical([2::5000,0::5000])::5000]) tabs:true editors: false;
		display map axes: false toolbar: false parent: base_map{}
		display farmer_indicators parent:base_farmer_indicators {}
		display environment_indicators parent:base_environment_indicators {}
		display input_indicators parent:base_input_indicators {}	
	} 
}



