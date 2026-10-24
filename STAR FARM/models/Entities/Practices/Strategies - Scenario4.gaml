/**
* Name: Strategy Scenario 1
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Strategies.gaml"

global {
	// Strategies IDs tested in Scenario 4
    string STRAT_SPOT_MIDDLEMEN <- "Spot_Market_Middlemen";
    string STRAT_COOP_CONTRACT <- "Formal_Cooperative_Contract";
}

/**
 * Scenario 4 - Branch A (Spot Market / Middlemen):
 * Conventional intensive practices sold to informal local collectors (thuong lai) under full price volatility.
 */
species Spot_Market_Middlemen parent: Agricultural_strategy {
    string id <- STRAT_SPOT_MIDDLEMEN;
    string short_name <- "Branch A: Spot Market (Middlemen)";
    rgb color <- rgb(211, 84, 0);

    bool has_cooperative_contract <- false;
    float quality_price_premium <- 0.0;
    float guaranteed_floor_multiplier <- 0.0;

    init {
        // Provincial targeted fruit baseline net revenue on uncertified spot market ($/ha/season)
        // Dong Thap: Mango (240$), An Giang: Pineapple (200$), Vinh Long: Coconut (220$)
        perennial_net_income_bonus <- (province = DONG_THAP) ? 240.0 : ((province = AN_GIANG) ? 200.0 : 220.0);

        map<int, bool> sowing_calendar <- [305::true, 115::false];

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
 * Scenario 4 - Branch B (Formal Value Chain / Cooperative Contract):
 * Certified 1Mha low-emission rice & agroecological fruits with guaranteed floor price and +10% quality premium.
 */
species Formal_Cooperative_Contract parent: Agricultural_strategy {
    string id <- STRAT_COOP_CONTRACT;
    string short_name <- "Branch B: Cooperative Contract (+10% Premium)";
    rgb color <- rgb(39, 174, 96);

    bool has_cooperative_contract <- true;
    float quality_price_premium <- 0.10;       // +10% quality premium for verified low-emission / agroecological standard
    float guaranteed_floor_multiplier <- 1.00; // Cooperative guarantees at least the baseline reference price (no crash below 1.0)

    init {
        // Certified agroecological fruit revenue with +10% cooperative quality premium
        float base_fruit_rev <- (province = DONG_THAP) ? 240.0 : ((province = AN_GIANG) ? 200.0 : 220.0);
        perennial_net_income_bonus <- base_fruit_rev * (1.0 + quality_price_premium);

        map<int, bool> sowing_calendar <- [305::true, 115::false];

        // Certified high-quality rice (ST25) with mechanical low-density seeding
        sowing <- world.create_sowing_practice(Cultivar first_with (each.name = "ST25"), sowing_calendar, true);
        harvesting <- world.create_harvesting_practice(true);

        ask world {
            // Mandatory AWD and reduced chemical protocol required by the cooperative contract
            do add_AWD_practice(myself);

            map<int, float> ftr;
            map<int, float> fta;
            map<int, float> pta;
            loop i from: 0 to: length(sowing_calendar) - 1 {
                int s_day <- sowing_calendar.keys[i];
                ftr[s_day] <- sust_n_trigger_threshold * fert_trigger_thresholds_coeff_2_seasons[i];
                // 20% cut in synthetic nitrogen (SSNM conditionality)
                fta[s_day] <- (bau_nitrogen_goal * 0.8) * fert_targets_coeff_2_seasons[i];
                pta[s_day] <- sust_pesticide_threshold * pesticide_thresholds_2_seasons[i];
            }
            do add_input_use_practice(cp: myself, trigger_thresholds_: ftr, base_dose_: (bau_n_dose_amount * 0.8), targets: fta, mech: false);
            do add_pesticide_practice(myself, pta, true, true);
            do add_fallow_practice(myself, fallow_day);
        }
        do initialize();
    }
}