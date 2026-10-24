/**
* Name: Strategy Scenario 1
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Strategies.gaml"


global {
	string STRAT_BAU_PREVENTIVE <- "BAU_Preventive";
    string STRAT_1M5R_ADAPTIVE <- "Sust_1M5R_Adaptive";
	
}
 
 
 /**
 * Scenario 2 - Branch A (Baseline 3 Seasons): 
 * Continuous Flooding (CF), High Nitrogen, and Preventive Spraying (Calendar-based)
 */
species BAU_Intensive_Preventive parent: Agricultural_strategy {
    string id <- STRAT_BAU_PREVENTIVE;
    string short_name <- "BAU 3S (CF + Preventive Spray)";
    rgb color <- rgb("#e74c3c"); // 

    init {
        // 3 Intensive rice cycles (Dong-Xuan, He-Thu, Thu-Dong)
        map<int, bool> sowing_calendar <- [320::true, 105::false, 210::false];
        
        // Standard seed rate (certified = false)
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM18"), sowing_calendar, false);
        harvesting <- world.create_harvesting_practice(false);

        ask world {
            do add_CF_practice(myself); // Continuous Flooding -> High Methane emissions

            map<int, float> ftr; 
            map<int, float> fta; 
            map<int, float> pta;
            
            loop i from: 0 to: length(sowing_calendar) - 1 {
                int s_day <- sowing_calendar.keys[i];
                ftr[s_day] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_3_seasons[i];
                fta[s_day] <- bau_nitrogen_goal * fert_targets_coeff_3_seasons[i];
                
                // Preventive / Prophylactic strategy: 
                // A negative threshold guarantees spraying strictly based on the calendar cooldown, ignoring pest density
                pta[s_day] <- -1.0;
            }
            
            // Standard Nitrogen dosage
            do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);
            
            // Preventive pesticides: is_biological = false, IPM = false
            do add_pesticide_practice(myself, pta, false, false);
            
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}

/**
 * Scenario 2 - Branch B (1Mha Programme / 1M5R): 
 * AWD, -20% Nitrogen (SSNM), Low Seed Rate, and Adaptive Spraying (Threshold-based)
 */
species Sust_1M5R_Adaptive parent: Agricultural_strategy {
    string id <- STRAT_1M5R_ADAPTIVE;
    string short_name <- "1M5R 3S (AWD + Adaptive Spray)";
    rgb color <- rgb(46, 204, 113);

    init {
        map<int, bool> sowing_calendar <- [320::true, 105::false, 210::false];
        
        // Low seed rate (<80kg/ha) simulated via mechanical = true
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM18"), sowing_calendar, true);
        harvesting <- world.create_harvesting_practice(true);

        ask world {
            do add_AWD_practice(myself); // Alternate Wetting & Drying -> GHG Mitigation

            map<int, float> ftr; 
            map<int, float> fta; 
            map<int, float> pta;
            loop i from: 0 to: length(sowing_calendar) - 1 {
                int s_day <- sowing_calendar.keys[i];
                ftr[s_day] <- sust_n_trigger_threshold * fert_trigger_thresholds_coeff_3_seasons[i];
                fta[s_day] <- (bau_nitrogen_goal * 0.8) * fert_targets_coeff_3_seasons[i];
                pta[s_day] <- sust_pesticide_threshold * pesticide_thresholds_3_seasons[i];
            }
            
            do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: (bau_n_dose_amount * 0.8), targets: fta, mech: false);
            do add_pesticide_practice(myself, pta, true, true);
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}