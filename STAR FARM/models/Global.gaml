/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

import "Entities/Parasite.gaml"

import "Entities/Weather.gaml"

import "Entities/Plant growth models.gaml"

import "Entities/Farms and Plots.gaml"

import "Parameters.gaml"

import "Constants.gaml"


global {
	
	geometry shape <- envelope(plots_shapefile);
	int init_day_of_year <-  current_date.day_of_year;
	

	
	init {
		do create_practices;
		do create_plant_growth_models;
		do create_plots; 
		do init_weather_data;
	
	}
	
	reflex start_parasite when: cycle = 450 {
		do create_parasites_and_predators;
	}
	
	action create_plots {
		create Plot from: plots_shapefile; 
		
		ask Plot {
			map attributes <- shape.attributes;
			loop att over: plots_to_keep.keys {
				if not(att in attributes.keys) or not(string(attributes[att]) contains plots_to_keep[att]) {
					do die;
				}
			}
			
			create Farm { 
				plots << myself; 
				create Farmer returns: f{
					my_farm <- myself;
					shape <-  union(myself.plots);
					
				}
				myself.the_farmer <- first(f);
			}
		}
		ask Farmer {
			do define_neighbors;
		}
	}
	
	
	
}

 