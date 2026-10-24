/**
* Name: Scenario4_exploration
* Author: Patrick Taillandier
* Description: Exploration of Scenario 4 (Market Dynamics, +30% Input Price Shock & Cooperative Contracts vs Middlemen)
*/

model Scenario4_exploration

import "../../Global.gaml"

global {
    int start_year <- 2028;
    int end_year <- 2045;
    
    // Cross-provincial scope: Dong Thap (Rice + Mango), An Giang (Rice + Pineapple), Vinh Long (Rice + Coconut)
    string province <- DONG_THAP among: [DONG_THAP, AN_GIANG, VINH_LONG];

    // Weather Scenario
    string BASELINE_WEATHER <- "Baseline_Weather";
    string weather_scenario <- BASELINE_WEATHER;

    // Market Scenarios: Standard vs +30% Fertilizer & Pumping Fuel Price Shock
    string STANDARD_MARKET <- "Standard";
    string INPUT_PRICE_SHOCK_30 <- "Input_Shock_Plus30pct";
    string market_scenario <- INPUT_PRICE_SHOCK_30 among: [STANDARD_MARKET, INPUT_PRICE_SHOCK_30];

    action init_action() {
        // Generate baseline climate
        do generate_scenario(BASELINE_WEATHER, start_year, end_year, 0.5, 1.0, 1.2, 0.0, 0, 0, prob_el_nino, prob_la_nina, el_nino_temp_offset, el_nino_rain_modifier);

        switch market_scenario {
            match STANDARD_MARKET {
                create Market {
                    market_id <- "Standard";
                    corr_water <- 0.8; 
                    trend_water <- 0.0;
                    corr_fertilizer <- 0.9; 
                    trend_fertilizer <- 0.0;
                    the_market <- self;
                }
            }
            match INPUT_PRICE_SHOCK_30 {
                create Market {
                    market_id <- "Input_Shock_Plus30pct";
                    // High volatility and upward trend on water/diesel and synthetic fertilizers
                    corr_water <- 0.3; 
                    trend_water <- 0.02; 
                    volatility_water <- 0.15;
                    corr_fertilizer <- 0.5; 
                    trend_fertilizer <- 0.02;
                    the_market <- self;
                }
            }
        }

        ask the_market {
            do generate_data(start_year, end_year);
            
            // Apply immediate +30% price shock on synthetic fertilizer and diesel pumping costs
            if (market_scenario = INPUT_PRICE_SHOCK_30) {
                loop y over: r_fertilizer.keys {
                    r_fertilizer[y] <- r_fertilizer[y] * 1.30;
                }
                loop y over: r_water.keys {
                    r_water[y] <- r_water[y] * 1.30;
                }
            }
        }
        
        output_folder <- "../../../scenario 4/" + province + "/" + first(possible_practices.keys) + "-" + market_scenario;
    }
}

// ----------------------------------------------------------------------
// EXPERIMENT: Full Matrix Exploration (Spot Middlemen vs Cooperative Contract x Market Shock x Provinces)
// ----------------------------------------------------------------------
experiment explore_scenario4 type: batch until: end_of_sim repeat: 20 keep_seed: true {
    parameter "Practice Strategy" var: possible_practices <- [STRAT_SPOT_MIDDLEMEN::1.0] among: [
        [STRAT_SPOT_MIDDLEMEN::1.0],                        // 100% Spot Market (Middlemen)
        [STRAT_COOP_CONTRACT::1.0],                         // 100% Formal Cooperative Contract
        [STRAT_SPOT_MIDDLEMEN::0.5, STRAT_COOP_CONTRACT::0.5] // 50/50 Mix to track endogenous farmer adoption rate
    ];
    parameter "Market Scenario" var: market_scenario among: [STANDARD_MARKET, INPUT_PRICE_SHOCK_30];
    parameter "Province" var: province among: [DONG_THAP, AN_GIANG, VINH_LONG];

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