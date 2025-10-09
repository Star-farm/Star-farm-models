/**
* Name: FarmsandPlots
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "Practices.gaml"

import "../Parameters.gaml"


species Farmer {
	Farm my_farm;
	
	Crop_practices practice <- practices[possible_practices.keys[rnd_choice(possible_practices.values)]];
	float money; 
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
	
}

species Farm { 
	list<Plot> plots;
}


species Plot {
	Farmer the_farmer;
	Crop associated_crop;
	
	reflex sowing when: current_date.day_of_year in the_farmer.practice.sowing_date{
		create Crop with:(the_farmer:the_farmer) {
			myself.associated_crop <- self;
			concerned_plot <- myself;
		} 
	}
	reflex harvesting when: current_date.day_of_year in the_farmer.practice.harvesting_date{
		the_farmer.money <- the_farmer.money + associated_crop.income_computation();
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
	
	
	float biomass_computation {
		return concerned_plot.shape.area * the_farmer.practice.Bmax / (1+ exp(-the_farmer.practice.k * (lifespan - the_farmer.practice.t0)));
	}
	float income_computation {
		return self.biomass_computation() * the_farmer.practice.Harvest_index * 1000.0 * the_farmer.practice.market_price;
	}
}
