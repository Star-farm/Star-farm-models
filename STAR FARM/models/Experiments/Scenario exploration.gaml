/**
* Name: Scenarioexploration
* Author: Patrick Taillandier
* Tags: 
*/


model Scenarioexploration

import "../Global.gaml"


global  {
	int start_year <- 2025;
    int end_year <- 2050;
    string OPTIMISTIC <- "Optimistic" ; 
    string BASELINE <- "Baseline" ;
    string PESSIMISTIC <- "Pessimistic";
     
    string STANDARD <- "Standard";
    string RESOURCE_CRISIS <- "Crisis"; 
     
      
	string weather_scenario <- OPTIMISTIC among: [OPTIMISTIC, PESSIMISTIC]   ;
	string market_scenario <- STANDARD among: [STANDARD, RESOURCE_CRISIS]   ;
	
	action init_action {
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
	}
	
		
}

experiment test_strategy type: batch until: end_of_sim repeat: 1 keep_seed: true {
	method exploration 
	with: [["possible_practices"::[BAU_3S_sust::1.0], "weather_scenario"::PESSIMISTIC,	"market_scenario"::STANDARD]];
	
	
	parameter possible_practices var: possible_practices <- [BAU_3S_sust::1.0] among:[[BAU_3S_sust::1.0]];
	parameter "weather scenario" var: weather_scenario  ;
	
	parameter "market scenario" var: market_scenario   ;
	
	init { 
		mode_batch <- true;
		save_results <- true; 
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 1;
		
		write_results <- true;
		day_start_of_year <- 300;
		starting_date <- date([2025,1,1]) add_days (day_start_of_year -1);
		use_weather_generator <- true;	
		use_dynamic_market <- true;
		
	}
}

experiment explore_strategies type: batch until: end_of_sim repeat: 20 keep_seed: true {
	//method exploration;
	parameter possible_practices var: possible_practices <- [BAU_3S::1.0] among:[[OMRH:: 1.0],[BAU_3S::1.0], [BAU_3S_sust::1.0],[BAU_2S::1.0]];
	parameter "weather scenario" var: weather_scenario  ;
	
	parameter "market scenario" var: market_scenario   ;
	
	init { 
		mode_batch <- true;
		save_results <- true; 
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 20;
		
		write_results <- false;
		day_start_of_year <- 300;
		starting_date <- date([2025,1,1]) add_days (day_start_of_year -1);
		use_weather_generator <- true;	
		use_dynamic_market <- true;
		
	}
}