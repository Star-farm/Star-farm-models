/**
* Name: AquaSpecies
* Description: Defines aquaculture species (shrimp, fish) traits and economic parameters.
* Author: Patrick Taillandier
*/

model STARFARM

import "../../Parameters.gaml"


global {
 
    action load_aquaspecies() { 
    	
        create Aqua_species from: aquaspecies_csv_file  ;
    }
}
  
species Aqua_species {
	string type;
  // Thermal & Cycle Parameters
    float t_base;                   // Minimum temperature for metabolic activity (°C)
    float t_opt;                    // Optimal temperature for growth (°C)
    float tt_maturity;              // Thermal time required to reach commercial harvest size (°C-days)
    
    // Growth & Biomass Parameters
    float base_growth_rate;         // Intrinsic daily growth rate (g/g/day)
    float carrying_capacity;        // Maximum biomass supported by the pond ecosystem (g/m², where 100 g/m² = 1 t/ha)
    float fcr;                      // Feed Conversion Ratio (kg of feed per kg of biomass gain)
    
    // Abiotic & Biotic Tolerance Thresholds
    float salinity_min;             // Minimum tolerable salinity (g/L)
    float salinity_max;             // Maximum tolerable salinity (g/L)
    float salinity_opt_min;         // Lower bound of optimal salinity range (g/L)
    float salinity_opt_max;         // Upper bound of optimal salinity range (g/L)
    float min_water_level;          // Minimum pond water depth required to buffer temperature and oxygen (mm)
    float pollution_sensitivity;    // Daily mortality rate per unit of pesticide pollution in the grid cell
    
    // Economic Parameters
    float market_price;             // Farm-gate selling price ($/kg)
    float stocking_unit_cost;       // Cost per post-larva or fingerling ($/individual)
    float default_stocking_density; // Default number of individuals stocked per hectare (ind/ha)
}