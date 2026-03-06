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
    
    bool fitness_computed <- false;
    action compute_fitness {
    	if not fitness_computed {
	    	fitness <- 0.0;
	    	string error_ <- "";
	    	loop ind over: indicators {
	    		float err <-  ind.compute_error();
	    		error_ <-error_ + err + ",";
	    		fitness <- fitness + err; 
	    	}
	    	string result <- "" + int(self)+ ","+ seed+","+ rue_efficiency_factor+ ","+pest_infection_prob+","+pest_daily_increment+"," +daily_water_loss_mm ;
	    	result <- result + ","+ error_+fitness+"\n";
	    	save result format: "text" to: calibration_output rewrite: false;
	    	fitness_computed <- true;
    	}
    }
   	
   
	action prepare_indicators {
		ask Avg_yield {
			store_values <- true;
			list<float> spring_2019_2023 <- [70,72.4,73.2,73.2,73.1];
			list<float> autumn_2019_2023 <- [60.5,61.3,61.8,63.2,62.8];
			list<float> winter_2019_2023 <- [39.6,42.3,45.6,42.1,39.1];
			loop i from: 0 to: length(spring_2019_2023) -1  {
				//conversion -> t/ha
				observed_values_per_seasons << spring_2019_2023[i]/10.0;
				observed_values_per_seasons << autumn_2019_2023[i]/10.0;
				observed_values_per_seasons << winter_2019_2023[i]/10.0;
			}
			
			indicators << self;
			
		}
		ask Avg_pesticide_applications {
			store_values <- true;
			observed_values_avg_total <- 5.5;
			indicators << self;	
		}
		ask Avg_irrigation_usage {
			store_values <- true;
			//conversion m3/ha -> mm/ha
			observed_values_avg_seasons << (8186 / 10.0);
			observed_values_avg_seasons << (5830 / 10.0);
			observed_values_avg_seasons << (2204 / 10.0);
			indicators << self;
		}
	}
	
		
}


experiment fine_tuning_yield type: batch until: end_of_sim repeat: 4 keep_seed: true {
	method reactive_tabu iter_max: 1000 cycle_size_max: 20 cycle_size_min: 20 tabu_list_size_init:10 minimize: fitness aggregation: "avr"
	init_solution: ["rue_efficiency_factor"::0.57, "daily_water_loss_mm"::12.0,	"pest_infection_prob"::0.4,	"pest_daily_increment"::0.01];

	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.5 max: 1.0 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.1 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.05 step:0.01;
	
	parameter daily_water_loss_mm var: daily_water_loss_mm min: 4.0 max: 12.0 step: 1.0;
		
	
	init {
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 4;
		mode_batch <- true;
		save_results <- false; 
		write_results <- false;
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- ["BAU-3seasons"::1.0];
   		starting_date <- date([2018,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,pest_infection_prob,pest_daily_increment,daily_water_loss_mm,error_yield,error_pesticide,error_water,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}

experiment calibration_yield_spray_water type: batch until: end_of_sim repeat: 4 keep_seed: true {
	method genetic pop_dim: 10 crossover_prob: 0.7 mutation_prob: 0.1 improve_sol: false stochastic_sel: false
	nb_prelim_gen: 2 max_gen: 10000  minimize: fitness  aggregation: "avr";
	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.5 max: 1.0 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.1 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.05 step:0.01;
	
	parameter daily_water_loss_mm var: daily_water_loss_mm min: 4.0 max: 12.0 step: 1.0;
	

	init {
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 4;
		mode_batch <- true;
		save_results <- false; 
		write_results <- false;
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- ["BAU-3seasons"::1.0];
   		starting_date <- date([2018,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,pest_infection_prob,pest_daily_increment,daily_water_loss_mm,error_yield,error_pesticide,error_water,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}