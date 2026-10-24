/**
* Name: Strategy Scenario 1
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Strategies.gaml"


global {
	  // Strategies IDs tested in Scenario 3
    string STRAT_RICE_SHRIMP_PINEAPPLE <- "Rice_Shrimp_Pineapple";
    string STRAT_RICE_PRAWN_COCONUT <- "Rice_Prawn_Coconut";
	
}

/**
 * Scenario 3 - Pathway A (An Giang / Dynamic Saline Threshold Shift):
 * Brackish Shrimp (Penaeus monodon) in dry season + Rainfed Rice (ST25) in wet season + Pineapple on raised beds
 */
species Rice_Shrimp_Pineapple parent: Agricultural_strategy {
    string id <- STRAT_RICE_SHRIMP_PINEAPPLE;
    string short_name <- "Rice-Shrimp + Pineapple (Dynamic)";
    rgb color <- #darkorange;

    // Net seasonal income bonus from pineapple cultivated on raised bunds ($/ha/season)
    float perennial_net_income_bonus <- 220.0;

    init {
        int shrimp_day <- 35; // Dry season stocking (early February)
        int rice_day <- 210;  // Wet season sowing (late July)

        // 1. Wet Season Rice Practices (Salinity-tolerant ST25)
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "ST25"), [rice_day::true], true);
        harvesting <- world.create_harvesting_practice(true);

        // 2. Dry Season Aquaculture Practices (Brackish Shrimp)
        Aqua_species shrimp_sp <- Aqua_species first_with (each.name = "PENAEUS_MONODON");
        aqua_stocking <- world.create_aqua_stocking_practice(shrimp_sp, [shrimp_day::true]);
        aqua_harvesting <- world.create_aqua_harvesting_practice();

        ask world {
            do add_AWD_practice(myself);
            do add_aqua_irrigating_practice(myself);
            do add_aqua_feeding_practice(myself, 10.0, 20.0, 60.0);

            // Reduced fertilizer input on rice thanks to shrimp organic sediment bonus
            do add_input_use_practice(
                cp: myself,
                trigger_thresholds_: [rice_day::(sust_n_trigger_threshold * 0.8)],
                base_dose_: (sust_n_dose_amount * 0.8),
                targets: [rice_day::(sust_nitrogen_goal * 0.6)],
                mech: false
            );

            // Complete suspension of synthetic chemical biocides (unreachable threshold 999.0)
            do add_pesticide_practice(myself, [rice_day::999.0], true, true);
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}

/**
 * Scenario 3 - Pathway B (Vinh Long / Freshwater Integrated System):
 * Freshwater Prawn (Macrobrachium) in rotation with Rice (ST25) and Elevated Coconut Groves
 */
species Rice_Prawn_Coconut parent: Agricultural_strategy {
    string id <- STRAT_RICE_PRAWN_COCONUT;
    string short_name <- "Rice-Prawn + Coconut (Vinh Long)";
    rgb color <- #teal;

    // Net seasonal income bonus from elevated coconut groves ($/ha/season)
    float perennial_net_income_bonus <- 260.0;

    init {
        int rice_day <- 315;  // Winter-Spring rice sowing (mid-November)
        int prawn_day <- 125; // Wet/Intermediate season freshwater prawn stocking (early May)

        // 1. Rice Season Practices
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "ST25"), [rice_day::true], true);
        harvesting <- world.create_harvesting_practice(true);

        // 2. Freshwater Prawn Aquaculture Practices
        Aqua_species prawn_sp <- Aqua_species first_with (each.name = "MACROBRACHIUM");
        aqua_stocking <- world.create_aqua_stocking_practice(prawn_sp, [prawn_day::true]);
        aqua_harvesting <- world.create_aqua_harvesting_practice();

        ask world {
            do add_AWD_practice(myself);
            do add_aqua_irrigating_practice(myself);
            do add_aqua_feeding_practice(myself, 10.0, 20.0, 60.0);

            // Reduced synthetic nitrogen thanks to prawn organic waste
            do add_input_use_practice(
                cp: myself,
                trigger_thresholds_: [rice_day::(sust_n_trigger_threshold * 0.8)],
                base_dose_: (sust_n_dose_amount * 0.8),
                targets: [rice_day::(sust_nitrogen_goal * 0.7)],
                mech: false
            );

            // Complete suspension of synthetic chemical pesticides to protect prawns
            do add_pesticide_practice(myself, [rice_day::999.0], true, true);
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}
