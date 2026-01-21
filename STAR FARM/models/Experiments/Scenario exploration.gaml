/**
* Name: Scenarioexploration
* Author: Patrick Taillandier
* Tags: 
*/


model Scenarioexploration

import "../Global.gaml"


experiment "explore strategies" type: batch until: end_of_sim repeat: 1 keep_seed: true {
	parameter possible_practices var: possible_practices <- ["BAU-3seasons"::1.0] among: [["BAU-3seasons"::1.0], ["BAU-2seasons"::1.0],["OMRH":: 1.0]];
	parameter weather_scenario var: weather_scenario ;
	
	init {
		mode_batch <- true;
		save_results <- true;
		write_results <- false;
		
	}
}