/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

import "Entities/Farms and Plots.gaml"

import "Parameters.gaml"

import "Constants.gaml"


global {
	float step <- 1 #day;
	
	date starting_date <- date([2026,8,1]);
	geometry shape <- envelope(plots_shapefile);
	 
	init {
		do create_crop_type;
		do create_plots;
	}
	
	action create_plots {
		create Plot from: plots_shapefile;
		
		ask Plot {
			create Farm { 
				plots << myself;
				create Farmer {
					my_farm <- myself;
				}
			}
		}
		ask Farmer {
			do define_associate_crop_type;
		}
	}
}

 