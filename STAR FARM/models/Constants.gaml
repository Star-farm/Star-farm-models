/**
* Name: Constants
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

global {
	
	
	
	/******* RICE GROTWH MODEL ********/
	string RICE <- "rice" const: true;
	string LUA_MD <- "lua md" const: true;
	
	/******* AQUA SPECIES GROTWH MODEL ********/
	string AQUA_SPECIES <- "aqua_species" const: true;
	string AQUA_MD <- "aqua_md";
	
	
	/******* INNOVATION DIFFUSION MODEL ********/
	string NONE <- "none" const: true;
	string NEIGHBORS <- "neighbors" const: true;
	
	
	/******* RICE ********/
	string RICE_AWD <- "Rice (Alt. Wetting and Drying)" const: true;
	string RICE_CF <- "Rice (Continuous Flooding)" const: true;
	
	string BAU_3S <- "BAU-3seasons" ; //BUSINESS AS USUAL 3 SEASONS
	string BAU_3S_AWD <- "BAU-awd" ; //BUSINESS AS USUAL 3 SEASONS - with AWD
	string BAU_2S <- "BAU-2seasons"; //BUSINESS AS USUAL 2 SEASONS
	string OMRH <- "OMRH" const: true; //ONE MILLION RICE HECTARES 
	string CUSTOM <- "custom" ;
	string RICE_SHRIMP <- "Rice_Shrimp";
	
	
	/******* RICE IRRIGATION *******/
	string CF <- "CF" const: true;
	string AWD <- "AWD" const: true;
	string NO_IRRIGATION <- "no_irrigation" const: true;
	
	string INPUT <- "input" const: true;
	string PESTICIDE <- "pesticide" const: true;
	
	string OM5451 <- "OM5451";
	string ST25 <- "ST25";
	
	
	/******* PROVINCE *******/
	string BEN_TRE <- "Ben Tre old";
	string DONG_THAP <- "Dong Thap";
	string DONG_THAP_OLD <- "Dong Thap old";
	string LONG_AN <- "Long An old";
	string TRA_VINH <- "Tra Vinh old";

}




