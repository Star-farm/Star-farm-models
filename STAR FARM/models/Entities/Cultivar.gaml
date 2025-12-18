/**
* Name: Cultivar
* Based on the internal empty template. 
* Author: patricktaillandier
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
	float photoperiod_sensitivity;   //0–1
	float max_LAI;   //  -
	float phyllochron;   //  °C·days / leaf
	float max_height;   //  cm
	float max_tillers;   //  tillers / plant
	float root_max_depth;   //  cm
	float RUE;   //  g DM / MJ
	float harvest_index_potential;   //  0–1
	float grain_filling_duration;   //  °C·days
	float grain_weight;   //  mg
	float drought_tolerance;   // 0–1
	float flood_tolerance;   //  0–1
	float salinity_tolerance;   //  0–1
	float heat_tolerance;   //  0–1
	float lodging_resistance;   // 0–1
	float nitrogen_response_eff;   // -
	float plant_density_opt;   // plants / m²
	float transplanting_suitability;   //  0–1
	float direct_seeding_suitability;   //  0–1
}
