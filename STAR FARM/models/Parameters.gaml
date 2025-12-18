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
	
	shape_file plots_shapefile <- shape_file("../includes/Dong Thap/2020/lu_dongthap2020-clean.shp");
	
	bool display_background <- true;
	
	image_file background_image_file <-display_background ?  image_file("../includes/Dong Thap/background.png") : image_file("../includes/Images/default_background.png");
 
	string weather_folder <- "../includes/An Bien/Weather";
	
	string innovation_diffusion_model <- NONE; //NONE, NEIGHBORS
   
    map<string, float> possible_practices <- [RICE_AWD::0.1, RICE_CF::0.9];
   
	map<string,string> plots_to_keep <- [];//["Lu05_en"::"Rice"];
		
	map<string,string> plant_grow_models <-[RICE_AWD::CERES, RICE_CF::CERES];// ORYZA ; //POSSIBLE VALUES : BASIC/CERES/ORYZA
	
	csv_file cultivars_csv_file <- csv_file("../includes/cultivars.csv", true);

	/******* PARAMETERS FOR ORYZA *********/
	 
	 map<string, string> data_files_practices <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_res.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_res.csv")
    ];
     map<string, string> data_files_yields <- [
        RICE_CF::("../includes/An Bien/Oryza/CF_s1/cf_op.csv"),
        RICE_AWD::("../includes/An Bien/Oryza/AWD_s1/awd_op.csv")
    ];
    
    /**** PARAMETERS FOR CERES PLANT GROWTH MODEL *****/
    float Tbase <- 8.0;
    float Topt_ceres  <- 30.0; 
    float k     <- 0.6;     // extinction coefficient 
    float P1    <- 500.0;   // °C.day emergence → panicle initiation
    float P5    <- 500.0;   // °C.day grain filling
    float RUE_ceres   <- 3.0;     // g DM / MJ
    
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
	float PD_target <- 50.0;    // hauteur de submersion cible (mm)
	float AWD_WTD_trigger <- 150.0; // seuil de ré-irrigation (mm)
	float CF_min_PD <- 20.0;
	


	// Paramètres du modèle avec pest(à calibrer)
	float init_pest_resistant_rate <- 0.25;
	int init_pest_number <- 15 min: 0;
	int init_predator_number <- 15 min: 0;
	
	int pest_day_lifespan <- 800;
	int predator_day_lifespan <- 800;
	
	float pest_quantity_B_to_eat <- 0.1;
	float pest_reprod_effi_rate <- 2.0; // Energy cost of reproduction

	float init_predator_resistant_rate <- 0.25;
	float predator_hunting_rate <- 0.8;
	float predator_reprod_effi_rate <- 20.0; // Energy cost of reproduction
	float predator_eating_effi_rate <- 0.02;
    
}

