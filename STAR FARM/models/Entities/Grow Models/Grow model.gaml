/**
* Name: Growmodel
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "../Weather.gaml"

import "../Market.gaml"

import "../../Parameters.gaml"
 
import "../Farms and Plots.gaml"

/* Insert your model definition here */

// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================

global {
 
	map<string, Growth_model> G_models;

	
	//action that creates at the initialization of the simulation the different plant growth models
	action create_growth_models() {
		loop s over: Growth_model.subspecies { 
			create s  ;
			
		}
		G_models[RICE] <- (agents of_generic_species Growth_model) first_with (each.id = rice_grow_model) ;
		G_models[AQUA_SPECIES] <- (agents of_generic_species Growth_model) first_with (each.id = aqua_species_grow_model) ;
	}	
} 




// ======================================================================
// GENERIC PLANT GROWTH MODEL SPECIES
// ======================================================================

species Growth_model virtual: true{
	string id; // Unique identifier for the model
	
	// Virtual methods to be implemented in derived models
	action day_biomass_growth(Crop c) virtual: true;	

} 
