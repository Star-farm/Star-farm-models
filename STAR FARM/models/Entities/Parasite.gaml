/**
* Name: Parasite
* Based on the internal empty template. 
* Author: roiarthurb
* Tags: 
*/

model Parasite

import "Farms and Plots.gaml"
import "../Parameters.gaml"

/* Insert your model definition here */

global {
	action create_parasites_and_predators{
		ask Farm {
			create Parasite number: rnd(init_parasite_number - 10, init_parasite_number + 10) {
				farm_to_eat <- myself;
			}
		}
		create Predator number: init_predator_number{
			location <- any_location_in(any(Farm));
		}
	}
}

species Parasite {
	bool resistant <- false;
	float energy <- 0.0;
	date date_of_birth;
	
	Farm farm_to_eat;
	Plot plot_to_eat <- nil;
	Crop crop_to_eat <- nil;
	
	init {
		if flip(init_parasite_resistant_rate) {
			resistant <- true;
		}
		date_of_birth <- current_date;
	}
	
	reflex eat when: (crop_to_eat != nil and !dead(crop_to_eat)) {
		float biomass_eaten <- min(parasite_quantity_B_to_eat, crop_to_eat.B);
		crop_to_eat.B <- crop_to_eat.B - biomass_eaten;
		
		if (crop_to_eat.B <= 0){
			ask crop_to_eat {
				write("Crop "+int(self)+" been entirely eaten");
				do die;
			}
			crop_to_eat <- nil;
		}
		
		energy <- energy + biomass_eaten;
	}
	
	reflex reproduction {
		loop times: int(energy / parasite_reprod_effi_rate) {
			create Parasite {
				farm_to_eat <- myself.farm_to_eat;
				plot_to_eat <- myself.plot_to_eat;
				resistant <- myself.resistant;
			}
			energy <- energy - parasite_reprod_effi_rate;
		}
	}
	
	reflex natural_death when: (current_date - date_of_birth >= parasite_day_lifespan # days){
		do die;
	}
	
	reflex change_eating_target when: crop_to_eat = nil  {
		Plot previousPlot <- plot_to_eat;
		list<Plot> otherPlotsToEat <- farm_to_eat.plots where (each.associated_crop != nil);
		if (length(otherPlotsToEat) > 0){
			plot_to_eat <- any(otherPlotsToEat where (each.associated_crop.B > 0));
			if (plot_to_eat = nil){
				// Restore previous plot, nothing to eat
				plot_to_eat <- previousPlot;
			} else {
				// New food
				crop_to_eat <- plot_to_eat.associated_crop;
				
				location <- any_location_in(plot_to_eat.shape);
			}	
		}
	}
	
	aspect default {
		draw circle(1) color: #red;
	}
}



species Predator skills: [moving] {
	float speed <- 20#m/#d;
	
	reflex move {
		do wander;
	}
		
	aspect default {
		draw triangle(50) color: #green;
	}
}












