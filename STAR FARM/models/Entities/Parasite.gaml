/**
* Name: Parasite
* Based on the internal empty template. 
* Author: roiarthurb
* Tags: 
*/

model Parasite

import "../Global.gaml"

import "Farms and Plots.gaml"
import "../Parameters.gaml" 



global {
	string map_display <- "Current practice";
	list<rgb> pest_density_palette <- brewer_colors("OrRd");
	int palette_size <- length(pest_density_palette);
	float palette_ceiling_value <- 1.0;
	
	species<Plot> plot_species <- species<Plot>("Plot_with_pest");
	
	// variable used temporarily to adjust the scale of the pest density. It has no use appart from that
	float max_pest_density <- 0.0;

	
	action create_pests_and_predators{ 
		
		loop times: init_pest_cluster_number {
			ask any(any(Farm).plots) {
				create BrownPlanthopper_Cluster number: 1 {					
					location <- any_location_in(myself);
					add [time, true, false, false] to: population;
				}
			}
			
		}
	}
	
	
	reflex start_pest when: cycle = 50 {
		do create_pests_and_predators;
	}
	
}


species Plot_with_pest parent: Plot{

	aspect default {
		if (map_display = "Current practice"){
			draw shape color: associated_crop = nil ? #white : the_farmer.practice.color border: #black;
		}else{
			float pest_density <- length(Pest_Cluster overlapping self) / self.shape.area * 10000;
			draw shape color: pest_density_palette[floor(min(pest_density/palette_ceiling_value,1)*(palette_size - 1))] border: #black;
		}
	}
}

species Pest_Cluster virtual: true parallel: true {
	float days_to_adult;
	float days_adult_lifespan;
	float days_to_hatch;
	
	int daily_max_eggs min: 0;
	
	float energy <- 10000.0;
	
	// date_of_birth, isResistant
	list<list> egg_population <- [];
	// date_of_birth, isFemale, isEgg, isAdult
	list<list> population <- [];
	
	init {
		loop times: rnd(1,daily_max_eggs) {
			do newEgg;
		}
	}
	
	//	==============================
	//		Life cycle
	//	==============================
	
	reflex natural_death when: length(population  where (each[3] = true)) > 0 {//when: isAdult and (current_date > date_of_birth + days_to_adult + days_adult_lifespan){
		loop parasite over: population where (each[3] = true) {
			if (time > (float(parasite[0]) + days_to_adult + days_adult_lifespan)) {
				remove parasite from: population;
			}
		}
	}
	
	reflex becomeAdult when: length(population where (each[2] = false and each[3] = false)) > 0 {//when: !isAdult and (current_date > date_of_birth + days_to_adult) {
		loop parasite over: population where (each[2] = false and each[3] = false) {
			if (time > (float(parasite[0]) + days_to_adult)) {
				parasite[3] <- true;
			}
		}
	}
	
	reflex hatching when: length(egg_population) > 0 {//when: isEgg and (current_date > date_of_birth + days_to_hatch) {
		loop i from: length(egg_population) - 1 to: 0 {
			if (time > (float(egg_population[i][0]) + days_to_hatch)) {
				// date_of_birth, isFemale, isResistant, isAdult
				add [time, flip(0.5), egg_population[i][1], false] to: population;
				
				remove egg_population[i] from: egg_population;	
			}
		}
	}
	
	reflex cluster_evolution when: energy > 0 {
		loop times: (population count (each[1] = true and each[3] = true)) * rnd(daily_max_eggs) {
			do newEgg;
			energy <- energy - 1;
		}
	}
	
	action newEgg {
		add [time, false] to: egg_population ;
	}
	
	aspect default {
		if (map_display = "Current practice"){
			draw circle((length(population) + length(egg_population))) color: #red;
		}
	}
}

// Win, S. S., Muhamad, R., Ahmad, Z. A., & Adam, N. A. (2011). Life table and population parameters of Nilaparvata lugens Stal.(Homoptera: Delphacidae) on rice. Tropical Life Sciences Research, 22(1), 25-35.
// https://apps.lucidcentral.org/pppw_v10/text/web_full/entities/rice_brown_planthopper_064.htm?utm_source=chatgpt.com
species BrownPlanthopper_Cluster parent: Pest_Cluster {
	float days_to_adult <- gauss_rnd(34,1)#days;
	float days_adult_lifespan <- gauss_rnd(20,2)#days;
	
	int daily_max_eggs <- 9;
	float days_to_hatch <- rnd(4,8)#days;
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
		loop prey over: Pest_Cluster at_distance hunting_radius {//Pest_Cluster where (each at_distance self > hunting_radius) {
			if flip(predator_hunting_rate) {
//				energy <- energy + (prey.energy*predator_eating_effi_rate);
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




