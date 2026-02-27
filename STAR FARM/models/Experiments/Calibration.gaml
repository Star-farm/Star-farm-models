/**
* Name: Scenarioexploration
* Author: Patrick Taillandier
* Tags: 
*/


model Calibration

import "../Global.gaml"


global  {
	 
    float fitness;
    
    list<Indicator> indicators;
    
    string calibration_output <- "Calibration/calibration_result.csv";
    
    action compute_fitness {
    	fitness <- 0.0;
    	loop ind over: indicators {
    		fitness <- fitness + ind.compute_error();
    	}
    	string result <- "" + int(self)+ ","+ seed+","+ rue_efficiency_factor+"," + flood_biomass_decay_rate+ ","+pest_infection_prob+"," +pest_daily_increment ;
    	result <- result + ","+fitness;
    	save result format: "text" to: calibration_output rewrite: false;
    }
   	
   
	action prepare_indicators {
		ask Avg_yield {
			store_values <- true;
						
			observed_values <- [7.32,6.18,4.56,7.32, 6.32, 4.21,7.31,6.28, 3.91];
			indicators << self;
		}
	}
	
		
}
experiment "explore strategies" type: batch until: end_of_sim repeat: 1 keep_seed: true {
	method genetic pop_dim: 3 crossover_prob: 0.7 mutation_prob: 0.1 improve_sol: true stochastic_sel: false
	nb_prelim_gen: 1 max_gen: 5  minimize: fitness  aggregation: "avr";
	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.5 max: 1.0 step: 0.01;
	parameter flood_biomass_decay_rate var: flood_biomass_decay_rate min: 0.01 max: 0.5 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.1 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.05 step:0.01;
	
	init {
		mode_batch <- true;
		save_results <- false;
		write_results <- false;
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- ["BAU-3seasons"::1.0];
   		starting_date <- date([2020,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,flood_biomass_decay_rate,pest_infection_prob,pest_daily_increment,fitness";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}