/**
* Name: Market
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/

model STARFARM

import "Biological Entities/Cultivar.gaml"
import "Biological Entities/Aqua Species.gaml"
import "Farms and Plots.gaml"

global {
	Market the_market;
	
    action init_market() {
		if (the_market = nil) {
			create Market {
				the_market <- self; 
			}	
		}
	}
}

species Market {
	
    rgb color_code;
	float global_inflation <- 0.005;
    float global_volatility <- 0.005;
    
    // --- 1. THE RATIOS (The Output) ---
    // All start at 1.0 (100% of the base price in your database)
    map<int,float> r_crop;            // Rice Output Price
    map<int,float> r_seeds;           // Rice Seed Price
    map<int,float> r_fertilizer;      // Chemical Fertilizer Price
    map<int,float> r_pesticides;      // Pesticide Price
    map<int,float> r_straw;           // Rice Straw Price
    map<int,float> r_water;           // Pumping Energy Price
    map<int,float> r_labor;           // Labor Wage Ratio
    map<int,float> r_mech;            // Mechanization/Fuel Ratio
    
    // Aquaculture-specific price ratios
    map<int,float> r_aqua;            // Aquaculture Output Price (Shrimp/Fish)
    map<int,float> r_aqua_stocking;   // Post-larvae / Fingerlings Price
    map<int,float> r_aqua_feed;       // Commercial Aquaculture Feed Price
    
	map<int,map<Cultivar,float>> specific_r_crop;
	map<int,map<Cultivar,float>> specific_r_seeds;
	map<int,map<Aqua_species,float>> specific_r_aqua;
	map<int,map<Aqua_species,float>> specific_r_aqua_stocking;

    // --- 2. CONTROL PARAMETERS (For each input/output) ---
    
    // SPECIFIC TRENDS (Added to global inflation)
    float trend_crop <- 0.0;
    float trend_seeds <- 0.01;        // Slight tech increase
    float trend_fertilizer <- 0.0;
    float trend_pesticides <- 0.0;
    float trend_water <- 0.0;
    float trend_labor <- 0.0;
    float trend_mech <- -0.03;
    float trend_straw <- 0.0;
    
    // Aquaculture Trends
    float trend_aqua <- 0.01;         // Strong global demand for shrimp/fish
    float trend_aqua_stocking <- 0.005;
    float trend_aqua_feed <- 0.01;
    
	map<Cultivar,float> specific_trend_crop;
	map<Cultivar,float> specific_trend_seeds;
	map<Aqua_species,float> specific_trend_aqua;
	map<Aqua_species,float> specific_trend_aqua_stocking;

    // GLOBAL CORRELATION (0.0 = Independent, 1.0 = Perfectly follows the market)
    float corr_crop <- 0.7;
    float corr_seeds <- 0.5;
    float corr_fertilizer <- 0.9;     // Highly linked to global energy costs
    float corr_pesticides <- 0.7;
    float corr_water <- 0.3;          // Often local/climate-based, loosely linked to inflation
    float corr_labor <- 0.9;
    float corr_mech <- 0.8;
    float corr_straw <- 0.6;
    
    // Aquaculture Correlations
    float corr_aqua <- 0.8;           // Export-oriented, sensitive to global economy
    float corr_aqua_stocking <- 0.5;
    float corr_aqua_feed <- 0.85;     // Linked to global fishmeal/soymeal commodities

	map<Cultivar,float> specific_corr_crop;
	map<Cultivar,float> specific_corr_seeds;
	map<Aqua_species,float> specific_corr_aqua;
	map<Aqua_species,float> specific_corr_aqua_stocking;
	
    // SPECIFIC VOLATILITY (Risk unique to the element)
    float volatility_water <- 0.05;
    float volatility_crop <- 0.10;    // Sale prices are often volatile
    float volatility_seeds <- 0.05;   
    float volatility_fertilizer <- 0.08;   
    float volatility_pesticides <- 0.05;  
    float volatility_straw <- 0.05;
    float volatility_mech <- 0.03;
    float volatility_labor <- 0.03;
    
    // Aquaculture Volatilities
    float volatility_aqua <- 0.18;    // Shrimp/Fish export prices experience higher volatility than rice
    float volatility_aqua_stocking <- 0.06;
    float volatility_aqua_feed <- 0.08;
    
	map<Cultivar,float> specific_volatility_crop;
	map<Cultivar,float> specific_volatility_seeds;
	map<Aqua_species,float> specific_volatility_aqua;
	map<Aqua_species,float> specific_volatility_aqua_stocking;
	
	// Market capacity (in tons) before the price starts to drop.
	map<Cultivar, float> market_saturation_threshold;
	map<Cultivar, float> price_sensitivity_k;
	Cultivar floor_price_cultivar;

	// Optional Market saturation parameters for Aquaculture species
	map<Aqua_species, float> aqua_market_saturation_threshold;
	map<Aqua_species, float> aqua_price_sensitivity_k;
	float aqua_floor_price_ratio <- 0.6; // Minimum floor price (60% of base price) under overproduction
	
	
	action compute_farmer_revenu() {
		// 1. Compute current Rice prices per Cultivar
		map<Cultivar,float> prices;
		loop c over: Cultivar {
			prices[c] <- the_market.r_for_crop(c) * c.rice_market_price;
		}
		
		// 2. Compute current Aquaculture prices per Aqua_species
		map<Aqua_species,float> aqua_prices;
		loop a over: Aqua_species {
			aqua_prices[a] <- the_market.r_for_aqua(a) * a.market_price;
		}

		// 3. Optional Market Retroaction (Overproduction price decay)
		if (add_market_retroaction) {
			// A. Rice supply & saturation
			float min_price <- (floor_price_cultivar != nil and floor_price_cultivar in prices.keys) ? prices[floor_price_cultivar] : 0.15;
			map<Cultivar,float> sum_yields;
			ask Plot where (each.is_active and not each.last_harvest_was_aqua and each.last_variety != nil) {
				sum_yields[last_variety] <- sum_yields[last_variety] + (actual_sold_yield * shape.area / 10000.0);
			} 
			loop c over: sum_yields.keys {
	        	float supply_ratio <- (c in market_saturation_threshold.keys and market_saturation_threshold[c] > 0) ? sum_yields[c] / market_saturation_threshold[c] : 0.0;
	       		if (supply_ratio > 1.0) {
	           		float decay <- exp(- price_sensitivity_k[c] * (supply_ratio - 1.0));
	            	prices[c] <- min_price + (prices[c] - min_price) * decay;
	         	}
	      	}

			// B. Aquaculture supply & saturation
			map<Aqua_species,float> sum_aqua_yields;
			ask Plot where (each.is_active and each.last_harvest_was_aqua and each.last_aqua_variety != nil) {
				sum_aqua_yields[last_aqua_variety] <- sum_aqua_yields[last_aqua_variety] + (actual_sold_yield * shape.area / 10000.0);
			}
			loop a over: sum_aqua_yields.keys {
				float supply_ratio <- (a in aqua_market_saturation_threshold.keys and aqua_market_saturation_threshold[a] > 0) ? sum_aqua_yields[a] / aqua_market_saturation_threshold[a] : 0.0;
				if (supply_ratio > 1.0) {
					float min_aqua_p <- aqua_prices[a] * aqua_floor_price_ratio;
					float decay <- exp(- aqua_price_sensitivity_k[a] * (supply_ratio - 1.0));
					aqua_prices[a] <- min_aqua_p + (aqua_prices[a] - min_aqua_p) * decay;
				}
			}
		}
		
		// 4. Allocate sales revenue to active plots and farmers
		ask Plot where (each.is_active) {
		    if (last_harvest_was_aqua and last_aqua_variety != nil) {
		        float aqua_rev <- (actual_sold_yield * 1000.0) * aqua_prices[last_aqua_variety];
		        the_farmer.revenue <- the_farmer.revenue + aqua_rev;
		    } else if (last_variety != nil) {
		        float rice_rev <- (actual_sold_yield * 1000.0) * prices[last_variety];
		        if (is_high_humidity) {
		            rice_rev <- rice_rev * grain_quality_discount_factor;
		        }
		        the_farmer.revenue <- the_farmer.revenue + rice_rev;
		    }
		}
		
		ask Farmer where (each.is_active) {
			profit_net <- revenue - total_costs;
			yearly_profit <- yearly_profit + profit_net;
		}
	}
	
	// --- SPECIFIC PARAMETER DEFINITIONS (RICE & AQUACULTURE) ---
	action define_specific_crop(Cultivar variety, float trend, float corr, float volatility) {
		specific_trend_crop[variety] <- trend;
		specific_corr_crop[variety] <- corr;
		specific_volatility_crop[variety] <- volatility;
	}
	
	action define_specific_seeds(Cultivar variety, float trend, float corr, float volatility) {
		specific_trend_seeds[variety] <- trend;
		specific_corr_seeds[variety] <- corr;
		specific_volatility_seeds[variety] <- volatility;
	}

	action define_specific_aqua(Aqua_species sp, float trend, float corr, float volatility) {
		specific_trend_aqua[sp] <- trend;
		specific_corr_aqua[sp] <- corr;
		specific_volatility_aqua[sp] <- volatility;
	}

	action define_specific_aqua_stocking(Aqua_species sp, float trend, float corr, float volatility) {
		specific_trend_aqua_stocking[sp] <- trend;
		specific_corr_aqua_stocking[sp] <- corr;
		specific_volatility_aqua_stocking[sp] <- volatility;
	}

	// --- RATIO GETTERS ---
	float r_for_seed(Cultivar variety) {
		if (current_date.year in specific_r_seeds.keys and variety in specific_r_seeds[current_date.year].keys) {
			return specific_r_seeds[current_date.year][variety];
		}
		if (current_date.year in r_seeds.keys) {
			return r_seeds[current_date.year];
		}
		return 1.0;
	}
	
	float r_for_crop(Cultivar variety) {
		if (current_date.year in specific_r_crop.keys and variety in specific_r_crop[current_date.year].keys) {
			return specific_r_crop[current_date.year][variety];
		}
		if (current_date.year in r_crop.keys) {
			return r_crop[current_date.year];
		}
		return 1.0;
	}

	float r_for_aqua(Aqua_species sp) {
		if (current_date.year in specific_r_aqua.keys and sp in specific_r_aqua[current_date.year].keys) {
			return specific_r_aqua[current_date.year][sp];
		}
		if (current_date.year in r_aqua.keys) {
			return r_aqua[current_date.year];
		}
		return 1.0;
	}

	float r_for_aqua_stocking(Aqua_species sp) {
		if (current_date.year in specific_r_aqua_stocking.keys and sp in specific_r_aqua_stocking[current_date.year].keys) {
			return specific_r_aqua_stocking[current_date.year][sp];
		}
		if (current_date.year in r_aqua_stocking.keys) {
			return r_aqua_stocking[current_date.year];
		}
		return 1.0;
	}
	
    // --- GENERIC CALCULATION ACTION ---
    action calculate_ratio(float current_ratio, float specific_trend, float correlation, float specific_vol, float global_shock) type: float {
        float local_shock <- gauss(0, specific_vol);
        float mixed_variation <- (correlation * global_shock) + ((1 - correlation) * local_shock);
        float new_ratio <- current_ratio * (1 + global_inflation + specific_trend + mixed_variation);
        
        if (new_ratio < 0.1) { return 0.1; } // Safety floor 
        return new_ratio;
    }
    
    action generate_data(int first_y, int last_y) {
    	loop y from: first_y to: last_y {
    		do annual_update(y);
    	} 
    }  

    action annual_update(int year) {
        // The "Economic Climate" of the year (Same for all inputs in this scenario)
        float world_shock <- gauss(0, global_volatility);
		int prev_year <- year - 1;
		bool first_y <- not(prev_year in r_crop.keys);
		
        // 1. Update general ratios
        r_crop[year] <- calculate_ratio(first_y ? 1.0 : r_crop[prev_year], trend_crop, corr_crop, volatility_crop, world_shock);
        r_seeds[year] <- calculate_ratio(first_y ? 1.0 : r_seeds[prev_year], trend_seeds, corr_seeds, volatility_seeds, world_shock);
        r_fertilizer[year] <- calculate_ratio(first_y ? 1.0 : r_fertilizer[prev_year], trend_fertilizer, corr_fertilizer, volatility_fertilizer, world_shock);
        r_pesticides[year] <- calculate_ratio(first_y ? 1.0 : r_pesticides[prev_year], trend_pesticides, corr_pesticides, volatility_pesticides, world_shock);
        r_water[year] <- calculate_ratio(first_y ? 1.0 : r_water[prev_year], trend_water, corr_water, volatility_water, world_shock);
        r_straw[year] <- calculate_ratio(first_y ? 1.0 : r_straw[prev_year], trend_straw, corr_straw, volatility_straw, world_shock);
        r_mech[year] <- calculate_ratio(first_y ? 1.0 : r_mech[prev_year], trend_mech, corr_mech, volatility_mech, world_shock);
        r_labor[year] <- calculate_ratio(first_y ? 1.0 : r_labor[prev_year], trend_labor, corr_labor, volatility_labor, world_shock);
        
        // 2. Update aquaculture general ratios
        r_aqua[year] <- calculate_ratio(first_y ? 1.0 : r_aqua[prev_year], trend_aqua, corr_aqua, volatility_aqua, world_shock);
        r_aqua_stocking[year] <- calculate_ratio(first_y ? 1.0 : r_aqua_stocking[prev_year], trend_aqua_stocking, corr_aqua_stocking, volatility_aqua_stocking, world_shock);
        r_aqua_feed[year] <- calculate_ratio(first_y ? 1.0 : r_aqua_feed[prev_year], trend_aqua_feed, corr_aqua_feed, volatility_aqua_feed, world_shock);

        // 3. Update cultivar-specific ratios (Rice)
        specific_r_crop[year] <- [];
        loop variety over: specific_trend_crop.keys {
        	float prev_val <- (first_y or not(variety in specific_r_crop[prev_year].keys)) ? 1.0 : specific_r_crop[prev_year][variety];
        	specific_r_crop[year][variety] <- calculate_ratio(prev_val, specific_trend_crop[variety], specific_corr_crop[variety], specific_volatility_crop[variety], world_shock);
        }
       
        specific_r_seeds[year] <- [];
        loop variety over: specific_trend_seeds.keys {
        	float prev_val <- (first_y or not(variety in specific_r_seeds[prev_year].keys)) ? 1.0 : specific_r_seeds[prev_year][variety];
        	specific_r_seeds[year][variety] <- calculate_ratio(prev_val, specific_trend_seeds[variety], specific_corr_seeds[variety], specific_volatility_seeds[variety], world_shock);
        }

        // 4. Update species-specific ratios (Aquaculture)
        specific_r_aqua[year] <- [];
        loop sp over: specific_trend_aqua.keys {
        	float prev_val <- (first_y or not(sp in specific_r_aqua[prev_year].keys)) ? 1.0 : specific_r_aqua[prev_year][sp];
        	specific_r_aqua[year][sp] <- calculate_ratio(prev_val, specific_trend_aqua[sp], specific_corr_aqua[sp], specific_volatility_aqua[sp], world_shock);
        }

        specific_r_aqua_stocking[year] <- [];
        loop sp over: specific_trend_aqua_stocking.keys {
        	float prev_val <- (first_y or not(sp in specific_r_aqua_stocking[prev_year].keys)) ? 1.0 : specific_r_aqua_stocking[prev_year][sp];
        	specific_r_aqua_stocking[year][sp] <- calculate_ratio(prev_val, specific_trend_aqua_stocking[sp], specific_corr_aqua_stocking[sp], specific_volatility_aqua_stocking[sp], world_shock);
        }
    }
}