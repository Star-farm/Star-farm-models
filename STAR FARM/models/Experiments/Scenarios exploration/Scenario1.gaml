/**
* Name: Scenario1_exploration
* Author: Patrick Taillandier
* Description: Exploration of Scenario 1 (El Niño 2027 Climate Shock & Sowing Calendar Shift)
*/

model Scenario1_exploration


import "../../Global.gaml" 

global {
    int start_year <- 2028;
    int end_year <- 2045;
    
    // Target province for Scenario 1 
    string province <- DONG_THAP among: [DONG_THAP, AN_GIANG, VINH_LONG];

    // Weather Scenarios: Normal baseline vs extreme El Niño 2027
    string BASELINE_WEATHER <- "Baseline_Weather";
    string EL_NINO_2027 <- "El_Nino_2027";
    string weather_scenario <- EL_NINO_2027 among: [BASELINE_WEATHER, EL_NINO_2027];

    // Market Scenario
    string STANDARD <- "Standard";
    string market_scenario <- STANDARD;

   
    action init_action() {
        switch weather_scenario {
            match BASELINE_WEATHER {
                // Standard climate without severe heat or salinity spikes
                do generate_scenario(BASELINE_WEATHER, start_year, end_year, 0.5, 1.0, 1.2, 0.0, 0, 0, prob_el_nino, prob_la_nina, el_nino_temp_offset, el_nino_rain_modifier);
            }
            match EL_NINO_2027 {
                // El Niño 2027: Delayed monsoon (+30d), early dry-season heat waves, Mekong flow deficit
                do generate_scenario(EL_NINO_2027, start_year, end_year, 2.5, 4.5, 1.6, 0.06, 30, 20, 0.40, 0.10, 1.5, 2.0);
            }
        }

        switch market_scenario {
            match STANDARD {
                create Market {
                    market_id <- "Standard";
                    corr_water <- 0.8; 
                    trend_water <- 0.0;
                    corr_fertilizer <- 0.9; 
                    trend_fertilizer <- 0.0;
                    the_market <- self;
                }
            }
        }

        ask the_market {
            do generate_data(start_year, end_year);
        }
        
       	output_folder <- "../../../scenario 1/" + province+ "/"+ first(possible_practices.keys) + "-"+weather_scenario;
			
    }
}

// ----------------------------------------------------------------------
// EXPERIMENT: Full Matrix Exploration (Baseline vs Adaptation x Climate)
// ----------------------------------------------------------------------
experiment explore_scenario1 type: batch until: end_of_sim repeat: 20 keep_seed: true {
    parameter "Practice Strategy" var: possible_practices <- [STRAT_BASE_OM18::1.0] among: [
        [STRAT_BASE_OM18::1.0], 
        [STRAT_ADAPT_OM9582::1.0]
    ];
    parameter "Weather Scenario" var: weather_scenario;
    parameter "Province" var: province;

    init {
        mode_batch <- true;
        save_yield_income_per_plots <- true;
        save_results <- true;
        write_results <- false;
        gama.pref_parallel_simulations_all <- false;
        gama.pref_parallel_threads <- 20;

        day_start_of_year <- 300;
        starting_date <- date([start_year, 1, 1]) add_days (day_start_of_year - 1);
        use_weather_generator <- true;
        use_dynamic_market <- true;
    }
}