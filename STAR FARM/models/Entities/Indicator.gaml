/**
* Name: Indicator
* Based on the internal empty template. 
* Author: Patrick Taillandier
* Tags: 
*/

model STARFARM

import "../Global.gaml"
 
global {
	// Definition of Indicator Categories
	string AGRO_ECONOMIC_PERFORMANCE <- "AGRO-ECONOMIC PERFORMANCE";
	string CLIMATE_MITIGATION <- "CLIMATE MITIGATION & GHG";
	string ADAPTATION_RESILIENCE <- "ADAPTATION & RESILIENCE";
	string RESOURCE_USE_SOIL <- "RESOURCE USE & SOIL HEALTH";
	string ECONOMIC_EQUALITY <- "ECONOMIC EQUALITY";
	
	map<string, Indicator> dayly_indicators;
	map<string, Indicator> seasonal_indicators;
	map<string, Indicator> yearly_indicators;
	
	map<string, list<float>> season_values;
	map<string, list<rgb>> color_values;
	
	action create_indicators() {
		loop s over: Indicator.subspecies { 
			create s returns: new_indicators;
			Indicator ct <- Indicator(first(new_indicators));
			
			if(ct.is_dayly) {
				dayly_indicators[ct.name] <- ct;
			}
			if(ct.is_seasonal) {
				seasonal_indicators[ct.name] <- ct;
				season_values[ct.legend] <- [];
				color_values[ct.legend] <- [];
			}
			if(ct.is_yearly) {
				yearly_indicators[ct.name] <- ct;
			}
		}
		do prepare_indicators();
	}
	
	action prepare_indicators() {
		
	}
}

species Indicator virtual: true {
	string name;
	string legend;
	string unit;
	string category;
	bool is_seasonal;
	bool is_yearly;
	bool is_dayly;
	int float_precision;
	float critic_value;
	bool critic_lower <- true;
	
	float value;
	bool store_values <- false;
	list<float> simulation_values;
	list<float> observed_values_per_seasons;
	list<float> observed_values_avg_seasons;
	list<bool> regroup_season;
	float observed_values_avg_total;
	list<int> non_representative_years;
	
	action generic_compute_value() {
		do compute_value();
		if (store_values and not(current_date.year in non_representative_years)) {
			simulation_values << value;
		}
		if (is_seasonal) {
			season_values[legend] << value;
			color_values[legend] << critic_lower ? ((value <= critic_value) ? #red : #green) : ((value >= critic_value) ? #red : #green);
		} 
	}
	action compute_value() virtual: true;
	 
	float compute_error() {
		float RMSE <- 0.0;
		float sum_obs; 
		int n <- 1;
		if not empty(observed_values_per_seasons) {
			list<float> adjusted_sim;
				
			if (not empty(regroup_season)) {
				list<float> sim_to_regroup;
				int num_regroup <- regroup_season count each;
				loop i from: 0 to: length(simulation_values) - 1 {
					if (regroup_season[i mod length(regroup_season)]) {
	        			sim_to_regroup << simulation_values[i];
	    			} else {
	        			adjusted_sim << simulation_values[i];
	    			}
					if (length(sim_to_regroup) = num_regroup) {
						adjusted_sim << mean(sim_to_regroup);
						sim_to_regroup <- [];
					}
	    		}
			}
			else {
				adjusted_sim <- simulation_values;
			}
			
			n <- min(length(observed_values_per_seasons), length(adjusted_sim));
			
			list<float> diffs;
			list<float> d_s <- [0,0,0];
			if (n > 0) {
				loop i from: 0 to: n - 1 {
					d_s[i mod 3] <- d_s[i mod 3] + (adjusted_sim[i] - observed_values_per_seasons[i]);
					diffs << (adjusted_sim[i] - observed_values_per_seasons[i]) with_precision 2;
					RMSE <- RMSE + (adjusted_sim[i] - observed_values_per_seasons[i]) ^ 2;	
					sum_obs <- sum_obs + observed_values_per_seasons[i];
				}
				RMSE <- sqrt(RMSE / n);
				if (write_calibration_result) {
					write "\n *** " + name + " obs: " + observed_values_per_seasons collect (each with_precision 2) + " sim: " + adjusted_sim collect (each with_precision 2) + " diff: " + (diffs) + " -> " + d_s;
				}
			}
		} else if not empty(observed_values_avg_seasons) {
			list<list<float>> f;
			n <- length(observed_values_avg_seasons);
			loop times: n {
				f << [];
			}
			loop i from: 0 to: length(simulation_values) - 1 {
				int ind <- i mod n;
				f[ind] << simulation_values[i];
			}
			if (write_calibration_result) {
				write "\n *** " + name + " obs: " + observed_values_avg_seasons + " sim: " + (f collect (mean(each)));
			}
			loop i from: 0 to: n - 1 {
				list<float> v <- f[i];
				float val_m <- sum(v);
				RMSE <- RMSE + (val_m / length(v) - observed_values_avg_seasons[i]) ^ 2;	
				sum_obs <- sum_obs + observed_values_avg_seasons[i];
			}
			RMSE <- sqrt(RMSE / n);
		} else {
			if (write_calibration_result) {
				write "\n *** " + name + " obs: " + observed_values_avg_total + " sim: " + mean(simulation_values);
			}
			RMSE <- abs(mean(simulation_values) - observed_values_avg_total);	
			sum_obs <- observed_values_avg_total;
		}
		if (sum_obs = 0) {
			return 0.0;
		}
		float mean_obs <- (sum_obs / n);
		return RMSE / mean_obs;
	}
}

// -----------------------------------------------------------
// SECTION 1: AGRO-ECONOMIC PERFORMANCE 
// -----------------------------------------------------------

species Avg_yield parent: Indicator {
	string name <- "Avg Yield";
	string legend <- "Avg Rice Yield";
	string unit <- "t/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	bool is_yearly <- false;
	bool is_dayly <- false;
	int float_precision <- 2;
	float critic_value <- 3.0;
	
	action compute_value() {
		// Filter strictly on plots that harvested Rice in this season
		list<Plot> rice_plots <- active_plots where not(each.last_harvest_was_aqua);
		if empty(rice_plots) { value <- 0.0; }
		else { value <- (rice_plots mean_of each.final_yield_ton_ha); }
	}
}

species Avg_shrimp_yield parent: Indicator {
	string name <- "Avg Shrimp Yield";
	string legend <- "Avg Shrimp Yield";
	string unit <- "t/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	bool is_yearly <- false;
	bool is_dayly <- false;
	int float_precision <- 2;
	float critic_value <- 0.25;
	
	action compute_value() {
		// Filter strictly on plots that harvested Shrimp in this season
		list<Plot> shrimp_plots <- active_plots where (each.last_harvest_was_aqua and each.last_aqua_variety != nil and each.last_aqua_variety.type = PROD_SHRIMP);
		if empty(shrimp_plots) { value <- 0.0; }
		else { value <- (shrimp_plots mean_of each.final_yield_ton_ha); }
	}
}

species Avg_fish_yield parent: Indicator {
	string name <- "Avg Fish Yield";
	string legend <- "Avg Fish Yield";
	string unit <- "t/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	bool is_yearly <- false;
	bool is_dayly <- false;
	int float_precision <- 2;
	float critic_value <- 1.0;
	
	action compute_value() {
		// Filter strictly on plots that harvested Fish in this season
		list<Plot> fish_plots <- active_plots where (each.last_harvest_was_aqua and each.last_aqua_variety != nil and each.last_aqua_variety.type = PROD_FISH);
		if empty(fish_plots) { value <- 0.0; }
		else { value <- (fish_plots mean_of each.final_yield_ton_ha); }
	}
}

species Avg_straw_value parent: Indicator {
	string name <- "Straw Value";
	string legend <- "Value of By-products (Straw)";
	string unit <- "$/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
 	action compute_value() {
		// Evaluated only on rice plots (aquaculture produces no straw)
		list<Plot> rice_plots <- active_plots where not(each.last_harvest_was_aqua);
		if empty(rice_plots) { value <- 0.0; }
		else { value <- mean(rice_plots collect (each.straw_yield_ton_ha * 1000 * straw_market_price)); }
	}
}

species Avg_production_cost parent: Indicator {
	string name <- "Production Cost";
	string legend <- "Avg Production Costs";
	string unit <- "$/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value() {
		if empty(active_farmers) { value <- 0.0; }
		else { value <- mean(active_farmers collect each.total_costs); }
	}
}

species Avg_net_income parent: Indicator {
	string name <- "Net Income";
	string legend <- "Net Farm Income";
	string unit <- "$/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value() {
		if empty(active_farmers) { value <- 0.0; }
		else { value <- mean(active_farmers collect each.profit_net); }
	}
}

species Avg_profit_margin parent: Indicator {
	string name <- "Profit Margin";
	string legend <- "Profit Margin";
	string unit <- "%";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 1;
	float critic_value <- 0.0;
	
	action compute_value() {
		if empty(active_farmers) { value <- 0.0; }
		else { value <- mean(active_farmers collect (float(each.profit_net) / float(max(1.0, each.revenue)) * 100)); }
	}
}

species Avg_labor_intensity parent: Indicator {
	string name <- "Labor Intensity";
	string legend <- "Avg Labor Intensity";
	string unit <- "hours/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value() {
		if empty(active_farmers) { value <- 0.0; }
		else { value <- mean(active_farmers collect each.accumulated_labor_hours); }
	}
}

// -----------------------------------------------------------
// SECTION 2: CLIMATE MITIGATION & GHG
// -----------------------------------------------------------

species Avg_methane parent: Indicator {
	string name <- "Methane Emissions";
	string legend <- "Avg Methane Emissions (CH4)";
	string unit <- "kg CH4/ha";
	string category <- CLIMATE_MITIGATION;
	bool is_seasonal <- true;
	int float_precision <- 0;
	float critic_value <- 300.0;
	bool critic_lower <- false;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- (active_plots mean_of each.methane_emissions_kg_ha); }
	}
} 

species AWD_adoption_rate parent: Indicator {
	string name <- "AWD Adoption";
	string legend <- "AWD Adoption Level";
	string unit <- "% area";
	string category <- CLIMATE_MITIGATION;
	bool is_seasonal <- true;
	int float_precision <- 1;
	
	action compute_value() {
		float total_area <- active_farmers sum_of each.plot_area;
		if (total_area > 0) {
			float awd_plots_area <- (active_farmers where (each.practice.irrigation != nil and each.practice.irrigation.name = AWD)) sum_of each.plot_area;
			value <- (awd_plots_area / total_area) * 100;
		} else {
			value <- 0.0;
		}
	} 
}

species Emission_intensity parent: Indicator {
	string name <- "Emission Intensity";
	string legend <- "GHG Emission Intensity";
	string unit <- "kg CH4/kg rice";
	string category <- CLIMATE_MITIGATION;
	bool is_seasonal <- true;
	int float_precision <- 3;
	float critic_value <- 1.0;
	bool critic_lower <- false;
	
	action compute_value() {
		list<Plot> rice_plots <- active_plots where not(each.last_harvest_was_aqua);
		if empty(rice_plots) { value <- 0.0; }
		else {
			float total_yield_tons <- (rice_plots sum_of each.final_yield_ton_ha);
			float total_ch4_kg <- (rice_plots sum_of each.methane_emissions_kg_ha);
			value <- total_ch4_kg / max(1.0, total_yield_tons * 1000);	  
		}
	}
}

// -----------------------------------------------------------
// SECTION 3: ADAPTATION & RESILIENCE
// -----------------------------------------------------------

species Safe_water_reliability parent: Indicator {
	string name <- "Water Reliability";
	string legend <- "Water Reliability (< tolerance)";
	string unit <- "% plots";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 1;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else {
			int plots_safe_salinity <- active_plots count (each.stress_days_salinity = 0);
	    	value <- (plots_safe_salinity / length(active_plots)) * 100;
		}
	}
}

species Resilient_variety_adoption parent: Indicator {
	string name <- "Resilient Varieties";
	string legend <- "Area under climate-resilient varieties";
	string unit <- "% area";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 1;
	
	action compute_value() {
		float total_area <- active_farmers sum_of each.plot_area;
		if (total_area > 0) {
			float plots_adapted <- (active_farmers where (
				(each.practice.sowing != nil and each.practice.sowing.type_of_cultivar.is_climate_resilient_variety) or
				(each.practice.aqua_stocking != nil)
			)) sum_of each.plot_area;
			value <- (plots_adapted / total_area) * 100;
		} else {
			value <- 0.0;
		}
	}
}

species Biodiversity_index parent: Indicator {
	string name <- "Biodiversity";
	string legend <- "Crop & Aqua Diversification Index";
	string unit <- "species/varieties";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value() {
		if empty(active_farmers) { value <- 0.0; }
		else {
			list<string> varieties <- [];
			loop f over: active_farmers {
				if (f.practice.sowing != nil and f.practice.sowing.type_of_cultivar != nil) {
					varieties << f.practice.sowing.type_of_cultivar.name;
				}
				if (f.practice.aqua_stocking != nil and f.practice.aqua_stocking.target_aqua_species != nil) {
					varieties << f.practice.aqua_stocking.target_aqua_species.name;
				}
			}
	    	value <- float(length(remove_duplicates(varieties)));
		}
	}
}

species Avg_salinity_stress_days parent: Indicator {
	string name <- "Salinity Stress";
	string legend <- "Avg Salinity Stress Days";
	string unit <- "days";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 2;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.stress_days_salinity); }
	}
}

species Avg_drought_stress_days parent: Indicator {
	string name <- "Drought Stress";
	string legend <- "Avg Drought Stress Days";
	string unit <- "days";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 2;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.stress_days_drought); }
	}
}

species Avg_flood_stress_days parent: Indicator {
	string name <- "Flood Stress";
	string legend <- "Avg Flood Stress Days";
	string unit <- "days";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 2;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.stress_days_flood); }
	}
}

species Avg_max_flood_continuous parent: Indicator {
	string name <- "Max Flood Continuous";
	string legend <- "Avg Max Continuous Flood Stress";
	string unit <- "days";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 2;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.max_stress_days_flood_continuous); }
	}
}

// -----------------------------------------------------------
// SECTION 4: RESOURCE USE & SOIL HEALTH
// -----------------------------------------------------------

species Avg_salinity_exposure parent: Indicator {
	string name <- "Salinity Exposure";
	string legend <- "Avg Salinity Exposure";
	string unit <- "g/l";
	string category <- RESOURCE_USE_SOIL;
	bool is_seasonal <- true;
	int float_precision <- 3;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.local_salinity); }
	}
}

species Avg_irrigation_usage parent: Indicator {
	string name <- "Water Usage";
	string legend <- "Irrigation Water Usage";
	string unit <- "mm/ha";
	string category <- RESOURCE_USE_SOIL;
	bool is_seasonal <- true;
	int float_precision <- 0;
	float critic_value <- 300.0;
	bool critic_lower <- false;
	
	action compute_value() {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.total_water_pumped); }
	}
}

species Avg_pesticide_applications parent: Indicator {
	string name <- "Pesticide Usage";
	string legend <- "Avg number of pesticide applications";
	string unit <- "count";
	string category <- RESOURCE_USE_SOIL;
	bool is_seasonal <- true;
	int float_precision <- 1;
	float critic_value <- 5.0;
	bool critic_lower <- false;
	
	action compute_value() {
		list<Plot> rice_plots <- active_plots where not(each.last_harvest_was_aqua);
		if empty(rice_plots) { value <- 0.0; }
		else { value <- mean(rice_plots collect each.pesticide_count); }
	}
}

species Avg_fertilizer_usage parent: Indicator {
	string name <- "Fertilizer Usage";
	string legend <- "Avg Fertilizer usage (Rice)";
	string unit <- "Kg N/ha";
	string category <- RESOURCE_USE_SOIL;
	bool is_seasonal <- true;
	int float_precision <- 1;
	float critic_value <- 100.0;
	bool critic_lower <- false;
	
	action compute_value() {
		list<Plot> rice_plots <- active_plots where not(each.last_harvest_was_aqua);
		if empty(rice_plots) { value <- 0.0; }
		else { value <- mean(rice_plots collect each.total_fertilizer_applied); }
	}
}

species Avg_aqua_feed_usage parent: Indicator {
	string name <- "Aqua Feed Usage";
	string legend <- "Avg Aquaculture Feed usage";
	string unit <- "Kg/ha";
	string category <- RESOURCE_USE_SOIL;
	bool is_seasonal <- true;
	int float_precision <- 1;
	float critic_value <- 150.0;
	bool critic_lower <- false;
	
	action compute_value() {
		list<Plot> aqua_plots <- active_plots where (each.last_harvest_was_aqua);
		if empty(aqua_plots) { value <- 0.0; }
		else { value <- mean(aqua_plots collect each.total_fertilizer_applied); }
	}
}

// -----------------------------------------------------------
// SECTION 5: YEARLY ECONOMIC INDICATORS
// -----------------------------------------------------------

species Gini_index parent: Indicator {
    string name <- "Gini Index";
    string legend <- "Gini Index (Inequality)";
    string unit <- "index";
    string category <- ECONOMIC_EQUALITY;
    bool is_seasonal <- false;
    bool is_yearly <- true;
    int float_precision <- 2;

    
    action compute_value() {
    list<float> farmer_profit <- Farmer collect each.yearly_profit;
	    if empty(farmer_profit) or (mean(farmer_profit) <= 0.0) { 
	        value <- 0.0; // Avoid meaningless negative Gini under systemic loss
	    } else { 
	        value <- gini(farmer_profit); 
	    }
	}
}

species Bankruptcy_risk parent: Indicator {
    string name <- "Bankruptcy Risk";
    string legend <- "Bankruptcy Risk (% farmers < 0)";
    string unit <- "%";
    string category <- ECONOMIC_EQUALITY;
    bool is_seasonal <- false;
    bool is_yearly <- true;
    int float_precision <- 1;

    action compute_value() {
        list<float> farmer_profit <- Farmer collect each.yearly_profit;
        if empty(farmer_profit) { value <- 0.0; }
        else {
            int negative_profits <- farmer_profit count (each < 0.0);
            value <- (negative_profits / length(farmer_profit)) * 100.0;
        }
    }
}




species Top20_Bottom20_Ratio parent: Indicator {
    string name <- "Top20/Bottom20 Ratio";
    string legend <- "Ratio Income Top 20% vs Bottom 20%";
    string unit <- "ratio";
    string category <- ECONOMIC_EQUALITY;
    bool is_seasonal <- false;
    bool is_yearly <- true;
    int float_precision <- 2;

   // In Top20_Bottom20_Ratio -> compute_value()
	action compute_value() {
	    list<float> farmer_profit <- (Farmer collect each.yearly_profit) sort_by each;
	    if (length(farmer_profit) < 5) { value <- 0.0; }
	    else {
	        int number <- round(0.2 * length(farmer_profit));
	        float mean_bottom <- mean(number first farmer_profit);
	        float mean_top <- mean(number last farmer_profit);
	        // If the bottom tier is in deficit, ratio is undefined/zero
	        value <- (mean_bottom <= 0.0) ? 0.0 : (mean_top / mean_bottom);
	    }
	}
}

species Coefficient_of_variation parent: Indicator {
    string name <- "CV Profit";
    string legend <- "Coefficient of Variation (Profit)";
    string unit <- "coef";
    string category <- ECONOMIC_EQUALITY;
    bool is_seasonal <- false;
    bool is_yearly <- true;
    int float_precision <- 2;

    action compute_value() {
        list<float> farmer_profit <- Farmer collect each.yearly_profit;
        if empty(farmer_profit) { value <- 0.0; }
        else {
            float avg_profit <- mean(farmer_profit);
            value <- (avg_profit = 0.0) ? 0.0 : (mean_deviation(farmer_profit) / avg_profit);
        }
    }
}