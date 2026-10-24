/**
* Name: Scenario2_exploration
* Author: Patrick Taillandier
* Description: Exploration of Scenario 2 (Sustainable Intensification 1M5R vs BAU Preventive)
*/

model Scenario2_exploration

import "../../Global.gaml"



global {
    int start_year <- 2028;
    int end_year <- 2045;
  
  // Normal climate baseline to isolate the effect of agronomic practices (no El Nino shock needed here)
    string BASELINE_WEATHER <- "Baseline_Weather";
    string weather_scenario <- BASELINE_WEATHER;

    string STANDARD_MARKET <- "Standard";
    string market_scenario <- STANDARD_MARKET;

    action init_action() {
        do generate_scenario(BASELINE_WEATHER, start_year, end_year, 0.5, 1.0, 1.2, 0.0, 0, 0, prob_el_nino, prob_la_nina, el_nino_temp_offset, el_nino_rain_modifier);

        create Market {
            market_id <- "Standard";
            corr_water <- 0.8; trend_water <- 0.0;
            corr_fertilizer <- 0.9; trend_fertilizer <- 0.0;
            the_market <- self;
        }

        ask the_market {
            do generate_data(start_year, end_year);
        }
        output_folder <- "../../../scenario 2/" + province+ "/"+ first(possible_practices.keys) + "-"+weather_scenario;
	
    }
    
}

// ----------------------------------------------------------------------
// EXPERIMENT: Explore Preventive vs Adaptive (3 Seasons) in Dong Thap
// ----------------------------------------------------------------------
experiment explore_scenario2 type: batch until: end_of_sim repeat: 5 keep_seed: true {
    
    // Compare the two branches defined in the Scenario
    parameter "Evaluated Practice" var: possible_practices <- [STRAT_BAU_PREVENTIVE::1.0] among: [
        [STRAT_BAU_PREVENTIVE::1.0], 
        [STRAT_1M5R_ADAPTIVE::1.0]
    ];
    
    parameter "Weather Scenario" var: weather_scenario <- BASELINE_WEATHER;
    parameter "Province" var: province <- DONG_THAP;

    init {
        mode_batch <- true;
        save_yield_income_per_plots <- true; // For gross margin stability analysis
        save_results <- true;
        write_results <- false;
        
        gama.pref_parallel_simulations_all <- false;
        gama.pref_parallel_threads <- 5;

        day_start_of_year <- 300;
        starting_date <- date([start_year, 1, 1]) add_days (day_start_of_year - 1);
        use_weather_generator <- true;
        use_dynamic_market <- true;
    }
}