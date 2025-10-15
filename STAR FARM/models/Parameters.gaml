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
	
	date starting_date <- date([2012,8,1]);
	
	image_file farmer_image <- image_file("../includes/Images/farmer.png");
	
	shape_file plots_shapefile <- shape_file("../includes/An Bien/an_bien_parcelles.shp");
	
	string weather_folder <- "../includes/An Bien/Weather";
	
	string innovation_diffusion_model <- NEIGHBORS; //NONE, NEIGHBORS
   
    map<string, float> possible_practices <- [RICE_AWD::0.1, RICE_CF::0.9];
   
	map<string,string> plots_to_keep <- ["Lu05_en"::"Rice"];
		
	string plant_grow_model <- BASIC;// ORYZA ; //POSSIBLE VALUES : BASIC/ORYZA

	/******* PARAMETERS FOR ORYZA *********/
	 
	 map<string, string> data_files_practices <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_res.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_res.csv")
    ];
     map<string, string> data_files_yields <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_op.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_op.csv")
    ];
    
    /**** PARAMETERS FOR BASIC PLANT GROWTH MODEL *****/
    
 	// Latitude pour ETo (en degrés)
	float latitude <- 10.0;

	// Paramètres du modèle (à calibrer)
	float alpha_par <- 0.48;    // fraction du rayonnement global converti en PAR
	float RUE <- 1.8;           // g MS / MJ PAR
	float k_LAI <- 0.5;         // coefficient d'extinction
	float aB <- 0.0025;         // m2 de feuille / g biomasse
	float m_resp <- 0.003;      // respiration quotidienne
	float HI <- 0.45;           // Harvest Index
	float S_max <- 150.0;       // réserve utile (mm)
	float S_opt_frac <- 0.7;
	float S_wp_frac <- 0.1;
	float N_opt <- 30.0;       // N optimal (kg/ha)
	float eta_N <- 0.015;       // % N dans biomasse
	float N_loss_frac <- 0.15;
	float PD_target <- 40.0;    // hauteur de submersion cible (mm)
	float AWD_WTD_trigger <- 150.0; // seuil de ré-irrigation (mm)
	float CF_min_PD <- 20.0;
	


    
}

