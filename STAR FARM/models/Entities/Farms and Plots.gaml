/**
* Name: FarmsandPlots
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "CropType.gaml"

species Farmer {
	Farm my_farm;
	float money;
	action define_associate_crop_type {
		loop p over: my_farm.plots {
			p.associated_crop_type <- Crop_types["Rice"];
		}
	}
}

species Farm {
	list<Plot> plots;
}

species Crop {
	Crop_type my_type; 
	float current_biomass;
	int lifespan <- 0 update: lifespan + 1;
	
	
	float biomass_computation {
		return shape.area * my_type.Bmax / (1+ exp(-my_type.k * (lifespan - my_type.t0)));
	}
	float income_computation {
		return self.biomass_computation() * my_type.Harvest_index * 1000.0 * my_type.current_price;
	}
}
species Plot {
	Crop associated_crop;
	Crop_type associated_crop_type;
	
	reflex sowing when: current_date.day_of_year in associated_crop_type.sowing_date{
		create Crop with:(my_type:associated_crop_type) {
			myself.associated_crop <- self;
		}
	}
	reflex harvesting when: current_date.day_of_year in associated_crop_type.harvesting_date{
		float revenu <- associated_crop.income_computation();
		
		ask associated_crop {
			do die;
		}
		associated_crop <- nil;
	}
	aspect default {
		draw shape color: associated_crop =nil ? #white : associated_crop.my_type.color border: #black;
	}
}
