/**
* Name: Scenario3_exploration
* Author: Patrick Taillandier
* Description: Exploration of Scenario 3 (Threshold-Based Agro-Ecological Diversification in An Giang & Vinh Long)
*/

model Scenario3_exploration

import "../../Global.gaml"

global {
    int start_year <- 2028;
    int end_year <- 2045;
    
    // Target provinces for Scenario 3
    string province <- AN_GIANG among: [AN_GIANG, VINH_LONG];

    // Weather Scenarios: Normal baseline vs Saline Intrusion Shock
    string BASELINE_WEATHER <- "Baseline_Weather";
    string SALINE_INTRUSION_SHOCK <- "Saline_Intrusion_Shock";
    string weather_scenario <- SALINE_INTRUSION_SHOCK among: [BASELINE_WEATHER, SALINE_INTRUSION_SHOCK];

    // Market Scenario
    string STANDARD <- "Standard";
    string market_scenario <- STANDARD;

  
    action init_action() {
        switch weather_scenario {
            match BASELINE_WEATHER {
                // Standard climate baseline
                do generate_scenario(BASELINE_WEATHER, start_year, end_year, 0.5, 1.0, 1.2, 0.0, 0, 0, prob_el_nino, prob_la_nina, el_nino_temp_offset, el_nino_rain_modifier);
            }
            match SALINE_INTRUSION_SHOCK {
                // Intensified dry-season saline intrusion to test the >4 g/L for >10 days dynamic conversion rule
                do generate_scenario(SALINE_INTRUSION_SHOCK, start_year, end_year, 2.0, 5.5, 1.5, 0.05, 30, 25, 0.35, 0.15, 1.2, 1.8);
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
        
        output_folder <- "../../../scenario 3/" + province + "/" + first(possible_practices.keys) + "-" + weather_scenario;
    }
}

// ----------------------------------------------------------------------
// EXPERIMENT: Full Matrix Exploration (Continuous Rice vs Agro-Ecological Diversification)
// ----------------------------------------------------------------------
experiment explore_scenario3 type: batch until: end_of_sim repeat: 5 keep_seed: true {
    parameter "Practice Strategy" var: possible_practices <- [BAU_2S::1.0] among: [
        [BAU_2S::1.0], 
        [STRAT_RICE_SHRIMP_PINEAPPLE::1.0],
        [STRAT_RICE_PRAWN_COCONUT::1.0]
    ];
    parameter "Weather Scenario" var: weather_scenario;
    parameter "Province" var: province;

    init {
        mode_batch <- true;
        save_yield_income_per_plots <- true;
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