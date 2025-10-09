/**
* Name: Parameters
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

import "Constants.gaml"

global {
	float step <- 1 #day;
	
	date starting_date <- date([2026,8,1]);
	
	
	shape_file plots_shapefile <- shape_file("../includes/An Bien/an_bien_parcelles.shp");

	
	string rice_grow_model <- BASIC ; //POSSIBLE VALUES : BASIC/ORYZA

	/******* PARAMETERS FOR ORYZA *********/
	 
	 map<string, file> data_files <- [
        RICE_CF::csv_file("../includes/An Bien/Oryza/CF_s1/cf_res.csv"),
        RICE_AWD::csv_file("../includes/An Bien/Oryza/AWD_s1/awd_res.csv")
    ];
    
    string innovation_diffusion_model <- NEIGHBORS; //NONE, NEIGHBORS
    map<string, float> possible_practices <- [RICE_AWD::0.1, RICE_CF::0.9];
    
}

