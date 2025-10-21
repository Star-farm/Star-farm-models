/**
* Name: Farms and Plots 
* Based on the internal empty template. 
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "Plant growth models.gaml"

import "Practices.gaml"

import "../Parameters.gaml"
 

species Farmer {
	Farm my_farm;
	
	Crop_practice practice <- practices[possible_practices.keys[rnd_choice(possible_practices.values)]];
	float money; 
	float water_usage update: my_farm.plots sum_of (each.associated_crop = nil ? 0.0 : each.associated_crop.irrigation_total);
	list<Farmer> neighbors;
	 
	action define_neighbors {
		neighbors <- Farmer at_distance 1.0;
	}
	
	action decide_practice {
		switch innovation_diffusion_model {
			match NEIGHBORS {
				do innovation_diffusion_neighbors;
			}
		}
	}
	 
	action innovation_diffusion_neighbors {
		map<string, float> practice_candidates;
		loop p over: possible_practices.keys {
			list<Farmer> p_farmers <- (neighbors + self) where (each.practice.id = p);
			if not empty(p_farmers) {
				practice_candidates[p] <- p_farmers mean_of (each.money);
			} 
		}
		if sum(practice_candidates.values) > 0.0 {
			practice <- practices[practice_candidates.keys[rnd_choice(practice_candidates.values)]];
		}
	}
	
	reflex change_practices when:cycle > 0 and current_date.day_of_year = init_day_of_year {
		do decide_practice;
	} 
	
	aspect default {
		draw farmer_image size: {50, 50} color: practice.color_farmer;
	}
}

species Farm { 
	list<Plot> plots;
}


species Plot { 
	Farmer the_farmer; 
	Crop associated_crop;
	
	reflex plantGrow when: associated_crop != nil {
		ask  PG_models[the_farmer.practice.id] {
			do biomass_computation_day(myself.associated_crop);
		}
	}
	reflex sowing when: PG_models[the_farmer.practice.id].is_sowing_date(the_farmer.practice){
		create Crop with:(the_farmer:the_farmer) {
			myself.associated_crop <- self;
			concerned_plot <- myself;
			crop_duration <-  PG_models[the_farmer.practice.id].compute_crop_duration(self);
			
		} 
	}
	
	
	reflex harvesting when:  PG_models[the_farmer.practice.id].is_harvesting_date(the_farmer.practice){
		the_farmer.money <-  associated_crop.income_computation();
		ask associated_crop { 
			do die; 
		} 
		associated_crop <- nil;
	}
	
	aspect default {
		draw shape color: associated_crop =nil ? #white : the_farmer.practice.color border: #black;
	}
}

species Crop {
	Farmer the_farmer;
	float current_biomass;
	Plot concerned_plot;
	int lifespan <- 0 update: lifespan + 1;
	int crop_duration;
	string irrigation_mode <- NO_IRRIGATION;
	float B <- 0.0;         // Biomasse (g/m²)
	float S <- S_max * 0.9;  // réserve en eau (mm)
	float PD <- PD_target;   // profondeur d’eau (mm)
	float N_avail <- 2.0;   // azote disponible (kg/ha)
	float irrigation_total ;
	int irrigation_events ;

	
	reflex fertilization when:lifespan in the_farmer.practice.fertilization.keys {
		float quantity <- the_farmer.practice.fertilization[lifespan];
		N_avail <- N_avail + quantity;
	}
	
	reflex change_irrigation when:lifespan in the_farmer.practice.irrigation.keys {
		irrigation_mode <- the_farmer.practice.irrigation[lifespan];
	} 
	
	float income_computation {
		return  PG_models[the_farmer.practice.id].biomass_computation(self) * 1000.0 * the_farmer.practice.market_price;
	}
}
