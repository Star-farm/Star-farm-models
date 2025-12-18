/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

//import "Entities/Parasite.gaml"

import "Entities/Weather.gaml"

import "Entities/Plant growth models.gaml"

import "Entities/Farms and Plots.gaml"

import "Parameters.gaml"

import "Constants.gaml"


global {
	
	geometry shape <- envelope(plots_shapefile);
	int init_day_of_year <-  current_date.day_of_year;
	
	
//	list<Plot> truc <- agents of_generic_species Plot;
		
	species<Plot> plot_species <- nil;
	int current_year -> int(ceil(cycle/365));

	
	init {
		do create_practices;
		do create_plant_growth_models;
		do create_plots;	
		do init_weather_data;
		ask remove_duplicates(PG_models){
			do initialize();
		} 
	}
	
	// this reflex is used to reset variables to their initial values everyday, at the begining of each step. 
	// putting reinit here avoids scheduler artefacts that would prevent reinitializing variables
	// at the wrong moment.
	reflex daily_reset{
		ask practices{
			day_income <- 0.0;
			day_expenses <- 0.0;
		}
	}
	
	action create_plots {
		if (plot_species = nil) {
			plot_species <- species<Plot>("Plot");
		}
		create plot_species from: plots_shapefile; 
//		create first(Plot.subspecies) from: plots_shapefile; 
		
		ask plot_species {
			map attributes <- shape.attributes;
			if not empty(plots_to_keep) {
				loop att over: plots_to_keep.keys {
					if not(att in attributes.keys) or not(string(attributes[att]) contains plots_to_keep[att]) {
						do die;
					}
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

 