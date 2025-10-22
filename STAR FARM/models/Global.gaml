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
	species<Plot> plot_species <- nil;

	
	init {
//		plot_species <- Plot;
		write Plot.subspecies;
//		plot_species <-  first(Plot.subspecies);
		do create_practices;
		do create_plant_growth_models;
		do create_plots; 
		
		do init_weather_data;
	
	}
	
	action create_parasites_and_predators;
	
	reflex start_parasite when: cycle = 450 {
		do create_parasites_and_predators;
	}
	
	
	
	action create_plots {
		if (plot_species = nil) {
			plot_species	<- species<Plot>("Plot");
		}
		create plot_species from: plots_shapefile; 
//		create first(Plot.subspecies) from: plots_shapefile; 
		
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

 