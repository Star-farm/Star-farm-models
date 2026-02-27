/**
* Name: Calibration
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
    	result <- result + ","+fitness+"\n";
    	save result format: "text" to: calibration_output rewrite: false;
    }
   	
   
	action prepare_indicators {
		ask Avg_yield {
			store_values <- true;
			list<float> spring_2019_2023 <- [70,72.4,73.2,73.2,73.1];
			list<float> autumn_2019_2023 <- [60.5,61.3,61.8,63.2,62.8];
			list<float> winter_2019_2023 <- [39.6,42.3,45.6,42.1,39.1];
			loop i from: 0 to: length(spring_2019_2023) -1  {
				observed_values << spring_2019_2023[i]/10.0;
				observed_values << autumn_2019_2023[i]/10.0;
				observed_values << winter_2019_2023[i]/10.0;
			}
			
			indicators << self;
			
		}
	}
	
		
}
experiment "calibration yield" type: batch until: end_of_sim repeat: 4 keep_seed: true {
	method genetic pop_dim: 10 crossover_prob: 0.7 mutation_prob: 0.1 improve_sol: true stochastic_sel: false
	nb_prelim_gen: 1 max_gen: 1000  minimize: fitness  aggregation: "avr";
	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.5 max: 1.0 step: 0.01;
	parameter flood_biomass_decay_rate var: flood_biomass_decay_rate min: 0.01 max: 0.5 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.1 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.05 step:0.01;
	
	init {
		gama.pref_parallel_simulations_all <- false;
		mode_batch <- true;
		save_results <- false; 
		write_results <- false;
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- ["BAU-3seasons"::1.0];
   		starting_date <- date([2018,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,flood_biomass_decay_rate,pest_infection_prob,pest_daily_increment,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}