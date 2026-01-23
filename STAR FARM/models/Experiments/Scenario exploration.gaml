/**
* Name: Scenarioexploration
* Author: Patrick Taillandier
* Tags: 
*/


model Scenarioexploration

import "../Global.gaml"


global  {
	int start_year <- 2026;
    int end_year <- 2049;
    string OPTIMISTIC <- "Optimistic" ;
    string BASELINE <- "Baseline" ;
    string PESSIMISTIC <- "Pessimistic";
    
    
	string weather_scenario <- BASELINE among: [OPTIMISTIC, BASELINE,PESSIMISTIC]   ;
	
	action init_action {
		switch weather_scenario {
			match OPTIMISTIC {
				do generate_scenario(OPTIMISTIC,start_year, end_year, 0.5, 1.0, 1.1, 0.0,0,0);
			}
			match BASELINE {
				do generate_scenario(BASELINE,start_year, end_year,1.2, 2.5, 1.25, 0.03,15,10);
			}
			match PESSIMISTIC{
				do generate_scenario(PESSIMISTIC,start_year, end_year, 2.5, 5.0, 1.4, 0.06,30,20);
			}
		}		
	}	
}
experiment "explore strategies" type: batch until: end_of_sim repeat: 1 keep_seed: true {
	parameter possible_practices var: possible_practices <- ["BAU-3seasons"::1.0] among: [["BAU-3seasons"::1.0], ["BAU-2seasons"::1.0],["OMRH":: 1.0]];
	parameter weather_scenario var: weather_scenario ;
	
	init {
		mode_batch <- true;
		save_results <- true;
		write_results <- false;
		use_weather_generator <- false;
		
	}
}