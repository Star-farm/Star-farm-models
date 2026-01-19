/**
* Name: Constants
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

global {
	/******* RICE GROTWH MODEL ********/
	string LUA_MD <- "lua md" const: true;
	string ORYZA <- "oryza" const: true;
	string CERES <- "ceres" const: true;
	
	
	/******* INNOVATION DIFFUSION MODEL ********/
	string NONE <- "none" const: true;
	string NEIGHBORS <- "neighbors" const: true;
	
	
	/******* RICE ********/
	string RICE_AWD <- "Rice (Alt. Wetting and Drying)" const: true;
	string RICE_CF <- "Rice (Continuous Flooding)" const: true;
	
	string BAU <- "BAU" const: true; //BUSINESS AS USUAL
	string OMRH <- "OMRH" const: true; //ONE MILLION RICE HECTARES 
	 
	/******* RICE IRRIGATION *******/
	string CF <- "CF" const: true;
	string AWD <- "AWD" const: true;
	string NO_IRRIGATION <- "no_irrigation" const: true;
	
	string INPUT <- "input" const: true;
	string PESTICIDE <- "pesticide" const: true;
}

