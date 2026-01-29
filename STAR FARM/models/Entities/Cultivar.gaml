/**
* Name: Cultivar
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM
 
import "../Parameters.gaml"


global {
	action load_cultivars {
		create Cultivar from: cultivars_csv_file;
	}
}

  
species Cultivar {
	
	float t_base;   // °C
	float tt_emergence;       // °C·days (planting → emergence)
	float tt_veg;     // °C·days (emergence → flowering)
	float tt_rep;       // °C·days (flowering → maturity)
	//float photoperiod_sensitivity;   //0–1
	//float max_LAI;   //  -
	//float phyllochron;   //  °C·days / leaf
	//float max_height;   //  cm
	//float max_tillers;   //  tillers / plant
	//float root_max_depth;   //  cm
	float RUE;   //  g DM / MJ
	float harvest_index_potential;   //  0–1
	float grain_filling_duration;   //  °C·days
	//float grain_weight;   //  mg
	float drought_tolerance;   // 0–1
	float flood_tolerance;   //  0–1
	float salinity_tolerance;   //  0–1
	float heat_tolerance;   //  0–1
	float lodging_resistance;   // 0–1
	float nitrogen_response_eff;   // -
//	float plant_density_opt;   // plants / m²
	//float transplanting_suitability;   //  0–1
	//float direct_seeding_suitability;   //  0–1
	int max_flood_tolerance_days ;// Number of days the plant can survive complete submergence (>30cm)
   
	
	// for CERES
	float N_max_conc <- 0.04;    // kg N / kg biomass (4%) (or g/g) : optimal N concentration of aerial biomass
    float N_min_conc <- 0.01;    // kg N / kg biomass (or g/g) structural minimum under which the growth stops
	float Zr_ini <- 50.0;    // root depth (mm)
	float Zr_max <- 400.0; // mm (riz)
	
// --- ECONOMIC PARAMETERS  ---
    float rice_market_price;        // Price in $ per kg of rice
    float seed_unit_cost;         // Seed cost in $ per hectare
	
	bool is_climate_resilient_variety <- compute_climate_resilient(self);
	
	
	bool compute_climate_resilient(Cultivar variety) {
    	if (variety.salinity_tolerance > 3.0 or variety.drought_tolerance > 0.7 or variety.flood_tolerance > 0.7) {
    	 	return true;
		} else {
    		return false;
    	}
	}
	
}

