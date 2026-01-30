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
	
	action create_indicators {
		loop s over: Indicator.subspecies { 
			create s returns: new_indicators;
			Indicator ct <- Indicator(first(new_indicators));
			if(ct.is_dayly) {
				dayly_indicators[ct.name] <- ct;
			}
			if(ct.is_seasonal) {
				seasonal_indicators[ct.name] <- ct;
			}
			if(ct.is_yearly) {
				yearly_indicators[ct.name] <- ct;
			}
		}
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
	int float_precision ;
	
	float value;
	
	action compute_value virtual: true;
}

// -----------------------------------------------------------
// SECTION 1: AGRO-ECONOMIC PERFORMANCE 
// -----------------------------------------------------------

species Avg_yield parent: Indicator {
	string name <- "Avg Yield";
	string legend <- "Avg Rice Yield";
	string unit <- "t/ha" ;
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	bool is_yearly <- false;
	bool is_dayly <- false;
	int float_precision <- 2;
	
	action compute_value {
		// (CTU 12) Avg Rice Yield
		if empty(active_plots) { value <- 0.0; }
		else { value <- (active_plots mean_of each.final_yield_ton_ha); }
	}
}

species Avg_straw_value parent: Indicator {
	string name <- "Straw Value";
	string legend <- "Value of By-products (Straw)";
	string unit <- "$/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value {
		// (CTU 13) Value of By-products
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect (each.straw_yield_ton_ha * 1000 * straw_market_price)); }
	}
}

species Avg_production_cost parent: Indicator {
	string name <- "Production Cost";
	string legend <- "Avg Production Costs";
	string unit <- "$/ha";
	string category <- AGRO_ECONOMIC_PERFORMANCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value {
		// (CTU 4) Avg Production Costs
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
	
	action compute_value {
		// (CTU 5) Net Farm Income
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
	
	action compute_value {
		// (CTU 8) Profit Margin
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
	
	action compute_value {
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
	
	action compute_value {
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
	
	action compute_value {
		float total_area <- active_farmers sum_of each.plot_area;
		if (total_area > 0) {
			float awd_plots_area <- (active_farmers where (each.practice.irrigation.name = AWD)) sum_of each.plot_area;
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
	
	action compute_value {
		if empty(active_plots) { value <- 0.0; }
		else {
			float total_yield_tons <- (active_plots sum_of each.final_yield_ton_ha);
			float total_ch4_kg <- (active_plots sum_of each.methane_emissions_kg_ha);
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
	
	action compute_value {
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
	
	action compute_value {
		float total_area <- active_farmers sum_of each.plot_area;
		if (total_area > 0) {
			float plots_adapted <- (active_farmers where each.practice.sowing.type_of_cultivar.is_climate_resilient_variety) sum_of each.plot_area;
			value <- (plots_adapted / total_area) * 100;
		} else {
			value <- 0.0;
		}
	}
}

species Biodiversity_index parent: Indicator {
	string name <- "Biodiversity";
	string legend <- "Crop Diversification Index";
	string unit <- "varieties";
	string category <- ADAPTATION_RESILIENCE;
	bool is_seasonal <- true;
	int float_precision <- 0;
	
	action compute_value {
		if empty(active_farmers) { value <- 0.0; }
		else {
			list<string> varieties <- active_farmers collect each.practice.sowing.type_of_cultivar.name;
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
	
	action compute_value {
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
	
	action compute_value {
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
	
	action compute_value {
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
	
	action compute_value {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.max_stress_days_flood_continuous); }
	}
}

species Avg_pest_load parent: Indicator {
    string name <- "Pest Pressure";
    string legend <- "Avg Pest Load Index";
    string unit <- "idx (0-1)";
    string category <- ADAPTATION_RESILIENCE;
    
    // Timing configuration for Daily output
    bool is_seasonal <- false;
    bool is_yearly <- false;
    bool is_dayly <- true;
    
    int float_precision <- 3; // Higher precision to detect small daily increments
    
    action compute_value {
        // (CTU Example) Average Pest Load across all active plots
        if empty(active_plots) { 
            value <- 0.0; 
        } else { 
            // Calculates the mean pest load stored on the plots
            value <- active_plots mean_of each.pest_load; 
        }
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
	
	action compute_value {
		// (CTU 19/38) Avg Salinity Exposure
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
	
	action compute_value {
		// (CTU 39) Irrigation Water Usage
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
	
	action compute_value {
		if empty(active_plots) { value <- 0.0; }
		else { value <- mean(active_plots collect each.pesticide_count); }
	}
}

// -----------------------------------------------------------
// SECTION: YEARLY ECONOMIC INDICATORS
// -----------------------------------------------------------

species Gini_index parent: Indicator {
    string name <- "Gini Index";
    string legend <- "Gini Index (Inequality)";
    string unit <- "index"; // 0 to 1
    string category <- ECONOMIC_EQUALITY;
    bool is_seasonal <- false;
    bool is_yearly <- true;
    int float_precision <- 2;

    action compute_value {
        // Collect all yearly profits
        list<float> farmer_profit <- Farmer collect each.yearly_profit;
        
        if empty(farmer_profit) { value <- 0.0; }
        else { value <- gini(farmer_profit); }
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

    action compute_value {
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

    action compute_value {
        // We must sort the list to identify Top and Bottom
        list<float> farmer_profit <- (Farmer collect each.yearly_profit) sort_by each;
        
        if (length(farmer_profit) < 5) { 
            value <- 0.0; // Not enough data for 20% split
        } else {
            int number <- round(0.2 * length(farmer_profit));
            
            // "first" returns the smallest values (Bottom 20%)
            // "last" returns the highest values (Top 20%)
            float mean_bottom <- mean(number first farmer_profit);
            float mean_top <- mean(number last farmer_profit);
            
            // Avoid division by zero
            value <- (mean_bottom = 0.0) ? 0.0 : (mean_top / mean_bottom);
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

    action compute_value {
        list<float> farmer_profit <- Farmer collect each.yearly_profit;
        
        if empty(farmer_profit) { value <- 0.0; }
        else {
            float avg_profit <- mean(farmer_profit);
            // Based on your formula: mean_deviation / mean
            value <- (avg_profit = 0.0) ? 0.0 : (mean_deviation(farmer_profit) / avg_profit);
        }
    }
}