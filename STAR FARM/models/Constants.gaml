/**
* Name: Constants
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

global {
	/******* RICE GROTWH MODEL ********/
	string BASIC <- "basic" const: true;
	string ORYZA <- "oryza" const: true;
	
	
	/******* INNOVATION DIFFUSION MODEL ********/
	string NONE <- "none" const: true;
	string NEIGHBORS <- "neighbors" const: true;
	
	
	/******* RICE ********/
	string RICE_AWD <- "rice_awd" const: true;
	string RICE_CF <- "rice_cf" const: true;
	
	/******* RICE IRRIGATION *******/
	string CONTINUOUS <- "continuous" const: true;
	string ALTERNATE <- "alternate" const: true;
	string NO_IRRIGATION <- "no_irrigation" const: true;
	
}

