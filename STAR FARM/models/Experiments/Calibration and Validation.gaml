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
    
    
    //2016-2022
    map<string, list<list<float>>> yield_values_per_case_study <-  [
    	DONG_THAP:: [[6.8,7.2,7.32,7.25,7.18,7.3,7.35],[5.7,5.6,6.21,6.28,6.34,6.4,6.42],[6.1,6.1,6.15,6.2,6.25,6.3,6.31]]
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
	    	
	    	string result <- "" + int(self)+ ","+ seed+","+ rue_efficiency_factor+ ","+pest_infection_prob+","+pest_daily_increment+"," +daily_water_loss_mm +","+max_water_capacity + "," + lateral_leakage_coefficient +","+ water_excess_coefficient+","+daily_n_consumption+","+toxicity_per_straw_unit;
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
			list<float> spring_2016_2023 <- data[0];
			list<float> autumn_2016_2023 <- data[1];
			list<float> winter_2016_2023 <- data[2] ;
			loop i from: 0 to: length(spring_2016_2023) -1  {
				//conversion -> t/ha
				observed_values_per_seasons << spring_2016_2023[i];
				observed_values_per_seasons << autumn_2016_2023[i];
				observed_values_per_seasons << winter_2016_2023[i];
				
			}
			
			indicators[self] <- 10.0;
			
		}
		
		ask Avg_irrigation_usage {
			store_values <- true;
			//conversion m3/ha -> mm/ha
			observed_values_avg_seasons << (8186 / 10.0);
			observed_values_avg_seasons << (5830 / 10.0);
			observed_values_avg_seasons << (2204 / 10.0);
			indicators[self] <- 1.0;
		}
		
		ask Avg_pesticide_applications {
			store_values <- true;
			observed_values_avg_seasons << 6;
			observed_values_avg_seasons << 5.5;
			observed_values_avg_seasons << 5;
			indicators[self] <- 1.0;
		}
		ask Avg_fertilizer_usage {
			store_values <- true;
			observed_values_avg_seasons << 132.0;
			observed_values_avg_seasons << 108.0;
			observed_values_avg_seasons << 84.0;
			indicators[self] <- 1.0;
		}
	}
	
		
}


experiment check_result type: batch until: end_of_sim repeat: 1 keep_seed: true {
	method exploration 
	with: ( [["write_calibration_result"::true]]);
	


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
   		starting_date <- date([2015,1,1]) add_days (day_start_of_year -1);
	}
} 


experiment calibration_ type: batch until: end_of_sim repeat: 4 keep_seed: true {
	//method genetic pop_dim: 10 crossover_prob: 0.7 mutation_prob: 0.1 improve_sol: false stochastic_sel: false
//	nb_prelim_gen: 2 max_gen: 10000  minimize: fitness  aggregation: "avr";
	method pso num_particles: 10 weight_inertia:0.7 weight_cognitive: 1.5 weight_social: 1.5  iter_max: 100 aggregation:"avr"  minimize: fitness  ; 
	
	parameter rue_efficiency_factor var: rue_efficiency_factor min: 0.3 max: 1.0 step: 0.01;
	
	parameter pest_infection_prob var: pest_infection_prob min: 0.4 max: 1.0 step: 0.1;
	
	parameter pest_daily_increment var: pest_daily_increment min: 0.01 max: 0.1 step:0.01;
	
	parameter daily_water_loss_mm var: daily_water_loss_mm min: 3.0 max: 15.0 step: 1.0;
	
	parameter max_water_capacity var: max_water_capacity min: 50.0 max: 120.0 step: 1.0;
	
	parameter lateral_leakage_coefficient var: lateral_leakage_coefficient min: 0.005 max: 0.05 step: 0.005;
	parameter water_excess_coefficient var: water_excess_coefficient min: 0.05 max: 0.4 step: 0.05;
	
	parameter daily_n_consumption var: daily_n_consumption min: 0.3 max:1.5 step: 0.1;
	
	parameter toxicity_per_straw_unit var: toxicity_per_straw_unit min: 0.001 max: 0.1 step: 0.001;
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
   		starting_date <- date([2015,1,1]) add_days (day_start_of_year -1);
   		string header <- "id,seed,rue_efficiency_factor,pest_infection_prob,pest_daily_increment,daily_water_loss_mm,max_water_capacity,lateral_leakage_coefficient,water_excess_coefficient,daily_n_consumption,toxicity_per_straw_unit,error_yield,error_pesticide,error_water,error_fertilizer,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}