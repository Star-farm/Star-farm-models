/**
* Name: Calibration
* Author: Patrick Taillandier 
* Tags: 
*/ 
   
 
model Calibration
 
import "../Global.gaml"

  
global  {   
	 
	 string DONG_THAP <- "Dong Thap";
	 float fitness;  
     
     map<Indicator, float> indicators;
    
    string calibration_output <- "Calibration/calibration_result.csv";
    
    string case_study <- DONG_THAP;
    
    
    map<string, list<list<float>>> yield_values_per_case_study <-  [
    	DONG_THAP:: [[72.4,73.2,73.2,73.1],[61.3,61.8,63.2,62.8],[42.3,45.6,42.1,39.1]]
    ];
   
    bool fitness_computed <- false;
    action compute_fitness() {
    	if not fitness_computed {
	    	fitness <- 0.0;
	    	string error_ <- "";
	    	float sum_weight <- 0.0;
	    	loop ind over: indicators.keys {
	    		float err <-  ind.compute_error();
	    		error_ <-error_ + err + ",";
	    		fitness <- fitness + (err * indicators[ind]); 
	    		sum_weight <- sum_weight + indicators[ind];
	    	}
	    	
	    	string result <- "" + int(self)+ ","+ seed+","+ rue_efficiency_factor+ ","+pest_infection_prob+","+pest_daily_increment+"," +daily_water_loss_mm +","+max_water_capacity + "," + toxicity_per_straw_unit;
	    	result <- result + ","+ error_+fitness+"\n";
	    	if (save_calibration_results) {
	    		save result format: "text" to: calibration_output rewrite: false;
	    	
	    	} else {
	    		write "\n" + result;
	    	}
	    	fitness_computed <- true; 
    	}
    }
   	
   
	action prepare_indicators() {
		ask Avg_yield {
			store_values <- true;
			list<list<float>> data <- yield_values_per_case_study[case_study];
			list<float> spring_2019_2023 <- data[0];
			list<float> autumn_2019_2023 <- data[1];
			list<float> winter_2019_2023 <-(length(data) > 2) ? data[2] : nil;
			loop i from: 0 to: length(spring_2019_2023) -1  {
				//conversion -> t/ha
				observed_values_per_seasons << spring_2019_2023[i]/10.0;
				observed_values_per_seasons << autumn_2019_2023[i]/10.0;
				if (winter_2019_2023 != nil) {
					observed_values_per_seasons << winter_2019_2023[i]/10.0;
				}
				
			}
			
			indicators[self] <- 10.0;
			
		}
		ask Avg_pesticide_applications {
			store_values <- true;
			observed_values_avg_seasons << 6;
			observed_values_avg_seasons << 5.5;
			observed_values_avg_seasons << 5;
			indicators[self] <- 1.0;
		}
		ask Avg_irrigation_usage {
			store_values <- true;
			//conversion m3/ha -> mm/ha
			observed_values_avg_seasons << (8186 / 10.0);
			observed_values_avg_seasons << (5830 / 10.0);
			observed_values_avg_seasons << (2204 / 10.0);
			indicators[self] <- 1.0;
		}
	}
	
		
}


experiment check_result type: batch until: end_of_sim repeat: 4 keep_seed: true {
	method exploration 
	with: ( [["daily_water_loss_mm"::10.0]]);
	


	init {
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 4;
		mode_batch <- true;
		save_results <- false; 
		write_results <- false;
		write_calibration_result <- true;     
		save_calibration_results <- false;
    
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- [BAU_3S::1.0];
   		starting_date <- date([2019,1,1]) add_days (day_start_of_year -1);
	}
}


experiment calibration_yield_spray_water type: batch until: end_of_sim repeat: 4 keep_seed: true {
	//method genetic pop_dim: 10 crossover_prob: 0.7 mutation_prob: 0.1 improve_sol: false stochastic_sel: false
//	nb_prelim_gen: 2 max_gen: 10000  minimize: fitness  aggregation: "avr";
	method pso num_particles: 10 weight_inertia:0.7 weight_cognitive: 1.5 weight_social: 1.5  iter_max: 100 aggregation:"avr"  minimize: fitness  ; 
	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.3 max: 1.0 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.4 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.1 step:0.01;
	
	parameter daily_water_loss_mm var: daily_water_loss_mm min: 7.0 max: 15.0 step: 1.0;
	
	parameter max_water_capacity var: max_water_capacity min: 50.0 max: 120.0 step: 1.0;
	
	parameter toxicity_per_straw_unit var: toxicity_per_straw_unit min: 0.1 max: 0.8 step: 1.0;
	init {
		gama.pref_parallel_simulations_all <- false;
		gama.pref_parallel_threads <- 4;
		mode_batch <- true;
		save_results <- false; 
		write_results <- false;
		write_calibration_result <- false;     
		save_calibration_results <- true;
 
		use_weather_generator <- false;
		innovation_diffusion_model <- NONE;
		possible_practices <- [BAU_3S::1.0];
   		starting_date <- date([2019,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,pest_infection_prob,pest_daily_increment,daily_water_loss_mm,max_water_capacity,toxicity_per_straw_unit,error_yield,error_pesticide,error_water,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}