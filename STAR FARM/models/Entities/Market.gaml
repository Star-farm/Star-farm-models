/**
* Name: Market
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "Cultivar.gaml"

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
	float global_inflation <- 0.03 ;
    float global_volatility <- 0.05 ;
    
    // --- 1. THE RATIOS (The Output) ---
    // All start at 1.0 (100% of the base price in your database)
     map<int,float> r_crop ;       // Output Price
     map<int,float> r_seeds ;
     map<int,float> r_fertilizer ;
     map<int,float> r_pesticides ;
     map<int,float> r_straw ;
     map<int,float> r_water ;
     map<int,float> r_mech ;      // Mechanization/Fuel
    
    
	 map<int,map<Cultivar,float>> specific_r_crop;
	 map<int,map<Cultivar,float>> specific_r_seeds;
	

    // --- 2. CONTROL PARAMETERS (For each input) ---
    
    // SPECIFIC TRENDS (Added to global inflation)
    // Ex: 0.0 = follows inflation. 0.05 = Inflation + 5%. -0.02 = Drop of 2%.
    float trend_crop <- 0.0;
    float trend_seeds <- 0.01; // Slight tech increase
    float trend_fertilizer <- 0.0;
    float trend_pesticides <- 0.0;
    float trend_water <- 0.0;
    float trend_mech <- 0.0;
    float trend_straw <- 0.0;
    
    
	map<Cultivar,float> specific_trend_crop;
	map<Cultivar,float> specific_trend_seeds;
	

    // GLOBAL CORRELATION (0.0 = Independent, 1.0 = Perfectly follows the market)
    float corr_crop <- 0.6;
    float corr_seeds <- 0.5;
    float corr_fertilizer <- 0.9; // Highly linked to global energy costs
    float corr_pesticides <- 0.7;
    float corr_water <- 0.3;      // Often local/climate-based, loosely linked to inflation
    float corr_mech <- 0.8;
    float corr_straw <- 0.6;


	map<Cultivar,float> specific_corr_crop;
	map<Cultivar,float> specific_corr_seeds;
	
	
    // SPECIFIC VOLATILITY (Risk unique to the element)
    float volatility_water <- 0.05; // Default
    float volatility_crop<- 0.1;   // Sale prices are often volatile
    float volatility_seeds <- 0.05;   
    float volatility_fertilizer <- 0.08;   
    float volatility_pesticides <- 0.05;  
    float volatility_straw <- 0.05;
    float volatility_mech <- 0.03;
    
    
	map<Cultivar,float> specific_volatility_crop;
	map<Cultivar,float> specific_volatility_seeds;
	
	
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

	float r_for_seed (Cultivar variety){
		if (variety in specific_r_seeds.keys) {
			return specific_r_seeds[current_date.year][variety];
		}
		return r_seeds[current_date.year];
	}
	
	float r_for_crop (Cultivar variety){
		if (variety in specific_r_crop.keys) {
			return specific_r_crop[current_date.year][variety];
		}
		return r_crop[current_date.year];
	}
	
    // --- GENERIC CALCULATION ACTION ---
    // This function prevents copy-pasting the same math formula 6 times
    action calculate_ratio (float current_ratio, float specific_trend, float correlation, float specific_vol, float global_shock) type: float {
        
        // 1. Shock specific to this input
        float local_shock <- gauss(0, specific_vol);
        
        // 2. Mix between global shock and local shock
        float mixed_variation <- (correlation * global_shock) + ((1 - correlation) * local_shock);
        
        // 3. Final Calculation: Inflation + Specific Trend + Variation
        float new_ratio <- current_ratio * (1 + global_inflation + specific_trend + mixed_variation);
        
        if (new_ratio < 0.1) { return 0.1; } // Safety floor 
        return new_ratio;
    }
    
    action generate_data(int first_year, int last_year) {
    	loop y from: first_year to: last_year{
    		do annual_update(y);
    	} 
    }

    action annual_update(int year) {
        // The "Economic Climate" of the year (Same for all inputs in this scenario)
        float world_shock <- gauss(0, global_volatility);

		int prev_year <- year - 1;
		bool first_year <- prev_year in r_crop.keys;
		
        // Update all ratios via the generic action
        r_crop[year] <- calculate_ratio(first_year ? 1.0 : r_crop[prev_year], trend_crop, corr_crop, volatility_crop, world_shock);
        r_seeds[year] <- calculate_ratio(first_year ? 1.0 : r_seeds[prev_year], trend_seeds, corr_seeds, volatility_seeds, world_shock);
        r_fertilizer[year] <- calculate_ratio(first_year ? 1.0 : r_fertilizer[prev_year], trend_fertilizer, corr_fertilizer,volatility_fertilizer , world_shock);
        r_pesticides[year] <- calculate_ratio(first_year ? 1.0 : r_pesticides[prev_year], trend_pesticides, corr_pesticides, volatility_pesticides, world_shock);
        r_water[year] <- calculate_ratio(first_year ? 1.0 : r_water[prev_year], trend_water, corr_water, volatility_water, world_shock);
        r_straw[year] <- calculate_ratio(first_year ? 1.0 : r_straw[prev_year], trend_straw, corr_straw, volatility_straw, world_shock);
        r_mech[year] <- calculate_ratio(first_year ? 1.0 : r_mech[prev_year], trend_mech, corr_mech, volatility_mech, world_shock);
        loop variety over: specific_trend_seeds.keys {
        	specific_r_crop[year][variety] <- calculate_ratio(first_year ? 1.0 : specific_r_crop[prev_year][variety] , specific_trend_crop[variety] , specific_corr_crop[variety] , specific_volatility_crop[variety] , world_shock);
        
        }
        loop variety over: specific_trend_seeds.keys {
        	specific_r_seeds[year][variety] <- calculate_ratio(first_year ? 1.0 : specific_r_seeds[prev_year][variety] , specific_trend_seeds[variety] , specific_corr_seeds[variety] , specific_volatility_seeds[variety] , world_shock);
        
        }
    }
}
