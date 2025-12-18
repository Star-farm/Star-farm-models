/**
* Name: Parasite
* Based on the internal empty template. 
* Author: roiarthurb
* Tags: 
*/

model Parasite

import "../Global.gaml"
import "../Experiments/Basic Experiments.experiment"  

import "Farms and Plots.gaml"
import "../Parameters.gaml" 



global {
	string map_display <- "Current practice";
	list<rgb> pest_density_palette <- brewer_colors("OrRd");
	int palette_size <- length(pest_density_palette);
	float palette_ceiling_value <- 0.1;
	
	species<Plot> plot_species <- species<Plot>("Plot_with_pest");
	
	// variable used temporarily to adjust the scale of the pest density. It has no use appart from that
	float max_pest_density <- 0.0;

	
	action create_pests_and_predators{ 
		
		ask Farm {
			create Pest number: rnd(init_pest_number - 10, init_pest_number + 10) {
				farm_to_eat <- myself;
			}
		}
		create Predator number: init_predator_number{
			location <- any_location_in(any(Plot));
		} 
	}
	
	
	reflex start_pest when: cycle = 450 {
		do create_pests_and_predators;
	}
	
}


species Plot_with_pest parent: Plot{

	aspect default {
		if (map_display = "Current practice"){
			draw shape color: associated_crop = nil ? #white : the_farmer.practice.color border: #black;
		}else{
			float pest_density <- length(Pest overlapping self)/self.shape.area;
//			max_pest_density <- max(max_pest_density, pest_density);
			draw shape color: pest_density_palette[floor(min(pest_density/palette_ceiling_value,1)*(palette_size - 1))] border: #black;

		}
	}
}

species Pest {
	bool resistant <- false;
	float energy <- 0.0;
	date date_of_birth;
	
	Farm farm_to_eat;
	Plot plot_to_eat <- nil;
	Crop crop_to_eat <- nil;
	
	init {
		if flip(init_pest_resistant_rate) {
			resistant <- true;
		}
		date_of_birth <- current_date;
	}
	
	reflex eat when: (crop_to_eat != nil and !dead(crop_to_eat)) {
		float biomass_eaten <- min(pest_quantity_B_to_eat, crop_to_eat.B);
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
		loop times: int(energy / pest_reprod_effi_rate) {
			create Pest {
				farm_to_eat <- myself.farm_to_eat;
				plot_to_eat <- myself.plot_to_eat;
				resistant <- myself.resistant;
			}
			energy <- energy - pest_reprod_effi_rate;
		}
	}
	
	reflex natural_death when: (current_date - date_of_birth >= pest_day_lifespan # days){
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
		if (map_display = "Current practice"){
			draw circle(1) color: #red;
		}
	}
}


 
species Predator skills: [moving] {
	float speed <- 15#m/#d;
	
	bool resistant <- false;
	float hunting_radius <- 40.0;
	float energy <- 0.0;
	date date_of_birth; 
	 
	init {
		if flip(init_predator_resistant_rate){
			resistant <- true;
		} 
		date_of_birth <- current_date;
	}
	
	reflex move {
		do wander; 
	}
	 
	reflex hunting {
		loop prey over: Pest at_distance hunting_radius {//Pest where (each at_distance self > hunting_radius) {
			if flip(predator_hunting_rate) {
				energy <- energy + (prey.energy*predator_eating_effi_rate);
				ask prey {
					do die;
				}
			}
		}
	}
	reflex reproduction {
		loop times: int(energy / predator_reprod_effi_rate ) {
			create Predator {
				resistant <- myself.resistant;
				location <- myself.location;
			}
			energy <- energy - predator_reprod_effi_rate;
		}
	}
	
	reflex natural_death when: (current_date - date_of_birth >= predator_day_lifespan # days){
		do die;
	}
		
	aspect default {
		if (map_display = "Normal"){
			draw circle(hunting_radius) color: #lightgreen border: #darkgreen;
			draw triangle(20) color: #green;
		}
	}
}

