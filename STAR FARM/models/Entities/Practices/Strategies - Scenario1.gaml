/**
* Name: Strategy Scenario 1
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Strategies.gaml"

global {
	 // Strategies IDs tested in Scenario 1
    string STRAT_BASE_OM18 <- "BAU_ElNino_Base";       // OM18, standard sowing (DOY 320)
    string STRAT_ADAPT_OM9582 <- "Adapt_ElNino_Shift15d"; // OM9582, advanced sowing (DOY 305)
 }
	

/**
 * Scenario 1 - Baseline: Standard sowing date with high-yield cultivar OM18
 */
species BAU_ElNino_Standard parent: Agricultural_strategy {
    string id <-STRAT_BASE_OM18;
    string short_name <- "Baseline OM18 (Standard Sowing)";
    rgb color <- #orange;

    init {
        // Standard sowing dates: Winter-Spring (Day 320), Summer-Autumn (Day 115)
        map<int, bool> sowing_calendar <- [320::true, 115::false];

        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM18"), sowing_calendar, false);
        harvesting <- world.create_harvesting_practice(false);

        ask world {
            do add_CF_practice(myself);

            map<int, float> ftr;
            map<int, float> fta;
            map<int, float> pta;
            loop i from: 0 to: length(sowing_calendar) - 1 {
                int s_day <- sowing_calendar.keys[i];
                ftr[s_day] <- bau_n_trigger_threshold * fert_trigger_thresholds_coeff_2_seasons[i];
                fta[s_day] <- bau_nitrogen_goal * fert_targets_coeff_2_seasons[i];
                pta[s_day] <- bau_pesticide_threshold * pesticide_thresholds_2_seasons[i];
            }
            do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: bau_n_dose_amount, targets: fta, mech: false);
            do add_pesticide_practice(myself, pta, false, false);
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}
 
/**
 * Scenario 1 - Adaptation: Sowing calendar advanced by 15 days with heat-tolerant cultivar OM9582
 */
species Adaptation_ElNino_Shift parent: Agricultural_strategy {
    string id <- STRAT_ADAPT_OM9582;
    string short_name <- "Adaptation OM9582 (-15d Sowing + AWD)";
    rgb color <- #dodgerblue;

    init {
        // Advanced sowing dates by 15 days: Winter-Spring (320 - 15 = 305), Summer-Autumn (115 - 15 = 100)
        map<int, bool> sowing_calendar <- [305::true, 100::false];

        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "OM9582"), sowing_calendar, true);
        harvesting <- world.create_harvesting_practice(true);

        ask world {
            do add_AWD_practice(myself);

            map<int, float> ftr;
            map<int, float> fta;
            map<int, float> pta;
            loop i from: 0 to: length(sowing_calendar) - 1 {
                int s_day <- sowing_calendar.keys[i];
                ftr[s_day] <- sust_n_trigger_threshold * fert_trigger_thresholds_coeff_2_seasons[i];
                fta[s_day] <- sust_nitrogen_goal * fert_targets_coeff_2_seasons[i];
                pta[s_day] <- sust_pesticide_threshold * pesticide_thresholds_2_seasons[i];
            }
            do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: sust_n_dose_amount, targets: fta, mech: false);
            do add_pesticide_practice(myself, pta, true, true);
            do add_fallow_practice(myself, fallow_day - 15);
        }
        do initialize();
    }
}