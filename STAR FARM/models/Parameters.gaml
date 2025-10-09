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
	
	image_file farmer_image <- image_file("../includes/Images/farmer.png");
	
	shape_file plots_shapefile <- shape_file("../includes/An Bien/an_bien_parcelles.shp");
	
	string innovation_diffusion_model <- NEIGHBORS; //NONE, NEIGHBORS
   
    map<string, float> possible_practices <- [RICE_AWD::0.1, RICE_CF::0.9];
   
	map<string,string> plots_to_keep <- ["Lu05_en"::"Rice"];
	
	string plant_grow_model <- ORYZA ; //POSSIBLE VALUES : BASIC/ORYZA

	/******* PARAMETERS FOR ORYZA *********/
	 
	 map<string, string> data_files_practices <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_res.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_res.csv")
    ];
     map<string, string> data_files_yields <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_op.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_op.csv")
    ];
    
    
}

