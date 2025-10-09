/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

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
		
	}
	
	action create_plots {
		create Plot from: plots_shapefile; 
		
		ask Plot {
			
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
	
	reflex change_practices when:cycle > 0 and current_date.day_of_year = init_day_of_year {
		ask Farmer {
			do decide_practice;
		}
	}
	
}

 