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
	    	result <- result + ","+// error_
	    	fitness+"\n";
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
   		ending_date <-  date([2024,1,1]);
	}
} 


experiment single_evaluation type: batch until: end_of_sim repeat: 1 keep_seed: true parent: generic_exp  {
	
  // 1,3.993681220280917E18,0.57,0.6,0.08,11.0,101.0,0.1,0.011215817939350649,0.2075636039539783,0.08279824749708323,
	
	parameter rue_efficiency_factor var: rue_efficiency_factor;
	parameter pest_infection_prob var: pest_infection_prob;
	parameter pest_daily_increment var: pest_daily_increment;
	parameter daily_water_loss_mm var: daily_water_loss_mm;
	parameter max_water_capacity var: max_water_capacity;
	parameter lateral_leakage_coefficient var: lateral_leakage_coefficient;
	parameter water_excess_coefficient var: water_excess_coefficient;
	parameter daily_n_consumption var: daily_n_consumption;
	parameter toxicity_per_straw_unit var: toxicity_per_straw_unit;
	
	method exploration 
	with: ( [["save_calibration_results"::true]]);
	
	
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
   		ending_date <-  date([2024,1,1]);
   		string header <- "id,seed,rue_efficiency_factor,pest_infection_prob,pest_daily_increment,daily_water_loss_mm,max_water_capacity,lateral_leakage_coefficient,water_excess_coefficient,daily_n_consumption,toxicity_per_straw_unit,error_yield,error_pesticide,error_water,error_fertilizer,fitness\n";
   		save header format: "text" to: calibration_output rewrite: true; 
	}
}