/**
 * ================================================================================================
 * Name: Plant growth models
 * Description:
 *   This model defines the different plant growth models used in the STARFARM simulation.
 *   It provides a global mechanism for initializing and managing crop growth models associated 
 *   with different agricultural practices. 
 *
 *   Two specific submodels are currently implemented:
 *     1. basicModel – A simple generic crop growth model based on climatic and water balance factors.
 *     2. Oryza – A model interfacing with external data files (from the ORYZA crop model) to simulate 
 *                rice growth based on precomputed yield data.
 *
 *   The models are designed to be called by each crop agent to compute daily biomass increments 
 *   and determine key phenological dates (sowing, harvesting, etc.).
 * 
 * Author: Patrick Taillandier
 * Tags: crop growth, irrigation, rice, Oryza, STARFARM
 *
 * ================================================================================================
 */

model STARFARM

import "../Parameters.gaml"

import "../Constants.gaml"

import "Weather.gaml"

 
import "Farms and Plots.gaml"

 
 

// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================

global {

	//map containing the Plant Grow Model associated to a practice (id of the practice)
	map<string,Plant_growth_model> PG_models;

	
	//action that creates at the initialization of the simulation the different plant growth models
	action create_plant_growth_models {
		map<string,Plant_growth_model> models;
		loop s over: Plant_growth_model.subspecies { 
			create s returns: new_practices;
			Plant_growth_model ct <- Plant_growth_model(first(new_practices));
			models[ct.id] <- ct ;
		}
		loop pract over: plant_grow_models.keys {
			PG_models[pract] <- models[plant_grow_models[pract]];
		}

// moved after the creation of every agents
//
//		ask remove_duplicates(PG_models){
//			do initialize();
//		} 
	}	
}




// ======================================================================
// GENERIC PLANT GROWTH MODEL SPECIES
// ======================================================================

species Plant_growth_model virtual: true{
	string id; // Unique identifier for the model
	
	// Virtual methods to be implemented in derived models
	float yield_computation(Crop c) virtual: true;	
	action day_biomass_growth(Crop c) virtual: true;	
	bool is_sowing_date(Crop_practice pr, int shift) virtual: true; // used a shift to compute the end of a season just one day after the harvest. Need to properly define when a season starts and ends.
	bool is_harvesting_date(Crop_practice pr, int shift) virtual: true; // used a shift to compute the end of a season just one day after the harvest. Need to properly define when a season starts and ends.
//	bool move_to_next_season(Crop_practice pr)


	
	action initialize;
	int compute_crop_duration(Crop c) {
		return 0;
	}
	
} 

// ======================================================================
// CERES CROP GROWTH MODEL
// ======================================================================

species ceresModel parent: Plant_growth_model {
	string id <- CERES;
	
   
    // --- STATE VARIABLES
    map<Plot,float> tt;        // thermal time
    map<Plot,int> stage;         // 0=veg, 1=repro, 2=grain fill, 3=mat
    float LAI <- 0.1;
//    float biomass <- 0.0;   // g/m²

 // --- SOIL WATER PARAMETERS
    float FC <- 200.0;    // field capacity (mm)
    float WP <- 80.0;     // wilting point (mm)
    float Zr <- 300.0;    // root depth (mm)

    // --- STATE VARIABLES
    map<Plot, float> soil_water;// <- 200.0;   // mm
    map<Plot, float> water_stress;   // 0–1
	
	// weather
	
	float tmax update: the_weather.temp_max[current_date];
	float tmin update: the_weather.temp_min[current_date];
	float precip update:  the_weather.rainfall[current_date];
	float sw update:  the_weather.solar_radiation[current_date];
	float Ra update:  compute_Ra();
	
	action initialize{
		 soil_water <- create_map(list<Plot>(Plot), list_with(length(Plot),200.0)) ;
		 water_stress <- create_map(list<Plot>(Plot), list_with(length(Plot),1.0)) ;
	}
		
	int compute_crop_duration(Crop c) {
		int start <- current_date.day_of_year;
		int index_start <- c.the_farmer.practice.sowing_date index_of start;
		int harvesting_date <-  c.the_farmer.practice.harvesting_date[index_start];
		if (harvesting_date < start) {
			harvesting_date <- harvesting_date + 365;
		}
		return harvesting_date - start;
	}
	
	
	float compute_Ra {
    // constants
    
    	float lat_deg <- CRS_transform(world.location, "4326").location.y;
    
		int doy <- current_date.day_of_year;
	    float PI <- 3.141592653589793;
	    float Gsc <- 0.0820; // MJ m-2 min-1, constante solaire
	
	    // convert latitude to radians
	    float lat_rad <- lat_deg * PI / 180.0;
	
	    // inverse relative distance Earth-Sun
	    float dr <- 1.0 + 0.033 * cos(2.0 * PI / 365.0 * doy);
	
	    // solar declination (radians)
	    float delta <- 0.409 * sin(2.0 * PI / 365.0 * doy - 1.39);
	
	    // sunset hour angle (radians)
	    float tmp <- -tan(lat_rad) * tan(delta);
	    // clamp tmp to [-1,1] to avoid NaN from acos for extreme lat/doy combos
	    if (tmp < -1.0) { tmp <- -1.0; }
	    if (tmp >  1.0) { tmp <-  1.0; }
	    float ws <- acos(tmp);
	
	    // Ra in MJ m-2 day-1
	    return (24.0 * 60.0 / PI) * Gsc * dr * ( ws * sin(lat_rad) * sin(delta) + cos(lat_rad) * cos(delta) * sin(ws) );
	}	
	
	float yield_computation(Crop c){
		return c.B * c.concerned_plot.shape.area / 10000; // kg per ha ?
	}
	
	// update phenology. Remark: all plots (and crops) share the same variables (temperature,
	// development stage, etc. This makes sense until data (weather...) is made spatially explicit.
	
	reflex phenology {
        float Tmean <- (tmax + tmin) / 2;
        float dTT <- max(0, Tmean - Tbase);
        ask Plot{
        	if (self.associated_crop = nil){
        		myself.tt[self] <- 0.0;
        		myself.stage[self] <- 0;
        	}else{
        		myself.tt[self] <- myself.tt[self] + dTT;
//        		if (int(self) = 0){
//        			write "stage "+myself.stage[self]+": "+myself.tt[self]+"/"+P1;
//        		}
        		if (myself.stage[self] = 0 and myself.tt[self] >= P1) { myself.stage[self] <- 1; }
		        if (myself.stage[self] = 1 and myself.tt[self] >= (P1 + P5)) { myself.stage[self] <- 2; }
		        if (myself.stage[self] = 2 and myself.tt[self] >= (P1 + 2 * P5)) { myself.stage[self] <- 3; }
        	}
        	
        }
    }
    
    // update soil water balance
    
    action soil_water_balance(Crop c)  {
    	Plot p <- c.concerned_plot;

		float inflow;
		
		// ETo (Hargreaves)
		float tmean <- (tmax + tmin) / 2.0;
		float ETo <- 0.0023 * (tmean + 17.8) * sqrt(max(0.0, tmax - tmin)) * Ra;
		
		// --- Irrigation logic
	    if (c.the_farmer.practice.id = RICE_CF) {
	    	if (soil_water[p] < FC) {
	        	inflow <- precip + (FC - soil_water[p]);
	        }
	    }else{
	        if (soil_water[p] < RiceAWD(c.the_farmer.practice).AWD_threshold * FC) {
	            inflow <- precip + RiceAWD(c.the_farmer.practice).irrigation_amount;
	        }
	    }
	
	    // --- Outflows
	    float transpiration <- ETo * water_stress[p];
	    float drainage <- max(0, soil_water[p] + inflow - FC);
	
	    // --- Update soil water
	    soil_water[p] <- soil_water[p] + inflow - transpiration - drainage;
	
	    soil_water[p] <- max(WP, min(soil_water[p], FC));
	     
	    
	    // update water stress
	    if (soil_water[p] <= WP) {
            water_stress[p] <- 0.0;
        }
        else if (soil_water[p] < FC) {
            water_stress[p] <- (soil_water[p] - WP) / (FC - WP);
        }
        else {
            water_stress[p] <- 1.0;
        }
    }
	
	
	action day_biomass_growth(Crop c){
		do soil_water_balance(c);

		if (stage[c.concerned_plot] < 3) {
            float IPAR <- Ra * (1 - exp(-k * LAI));
            float dBiomass <- IPAR * RUE_ceres * water_stress[c.concerned_plot];

            c.B <- c.B + dBiomass;

            // simple LAI expansion
            LAI <- LAI + 0.01 * dBiomass;
        }
	}
		
	bool is_sowing_date (Crop_practice pr, int shift){	
		return (current_date.day_of_year + shift) in pr.sowing_date ;
	}
	bool is_harvesting_date(Crop_practice pr, int shift) {
		return (current_date.day_of_year + shift)  in pr.harvesting_date ;
	}


	
}



// ======================================================================
// BASIC CROP GROWTH MODEL
// ======================================================================


species basicModel parent: Plant_growth_model {
	string id <- BASIC;
	
	float tmax update: the_weather.temp_max[current_date];
	float tmin update: the_weather.temp_min[current_date];
	float precip update:  the_weather.rainfall[current_date];
	float sw update:  the_weather.solar_radiation[current_date];
	float Ra update:  compute_Ra();
		
	int compute_crop_duration(Crop c) {
		int start <- current_date.day_of_year;
		int index_start <- c.the_farmer.practice.sowing_date index_of start;
		int harvesting_date <-  c.the_farmer.practice.harvesting_date[index_start];
		if (harvesting_date < start) {
			harvesting_date <- harvesting_date + 365;
		}
		return harvesting_date - start;
	}
	
	float compute_Ra {
    // constants
    
    	float lat_deg <- CRS_transform(world.location, "4326").location.y;
    
		int doy <- current_date.day_of_year;
	    float PI <- 3.141592653589793;
	    float Gsc <- 0.0820; // MJ m-2 min-1, constante solaire
	
	    // convert latitude to radians
	    float lat_rad <- lat_deg * PI / 180.0;
	
	    // inverse relative distance Earth-Sun
	    float dr <- 1.0 + 0.033 * cos(2.0 * PI / 365.0 * doy);
	
	    // solar declination (radians)
	    float delta <- 0.409 * sin(2.0 * PI / 365.0 * doy - 1.39);
	
	    // sunset hour angle (radians)
	    float tmp <- -tan(lat_rad) * tan(delta);
	    // clamp tmp to [-1,1] to avoid NaN from acos for extreme lat/doy combos
	    if (tmp < -1.0) { tmp <- -1.0; }
	    if (tmp >  1.0) { tmp <-  1.0; }
	    float ws <- acos(tmp);
	
	    // Ra in MJ m-2 day-1
	    return (24.0 * 60.0 / PI) * Gsc * dr * ( ws * sin(lat_rad) * sin(delta) + cos(lat_rad) * cos(delta) * sin(ws) );
	}
	
	
	float yield_computation(Crop c) {
		
		return c.B * c.concerned_plot.shape.area / 10000; // kg per ha ?
	}

	action day_biomass_growth(Crop c) {
		
		float tmean <- (tmax + tmin) / 2.0;

	
		// ETo (Hargreaves)
		float ETo <- 0.0023 * (tmean + 17.8) * sqrt(max(0.0, tmax - tmin)) * Ra;
		// Coeff Kc selon stade
		float frac <- c.lifespan / (c.crop_duration);
		float Kc <- (frac < 0.35) ? 0.9 : (frac < 0.8 ? 1.05 : 0.95);
		float ETc <- Kc * ETo;

		// Gestion irrigation
		float I <- 0.0;
		c.PD <- c.PD + precip;

		if (c.the_farmer.practice.id = RICE_CF) {
			if (c.PD < CF_min_PD) {
				I <- PD_target - c.PD;
				c.PD <- c.PD + I;
			}
		} else { // AWD
			if (c.PD <= 0 and c.S < AWD_WTD_trigger) {
				I <- PD_target - c.PD;
				c.PD <- c.PD + I;
			}
		}
		
		
		if (I > 0) {
			c.irrigation_total <- c.irrigation_total + I;
			c.irrigation_events <- c.irrigation_events + 1;
		}

		// ET -> perte d'eau
		if (c.PD > 0) {
			c.PD <- max(0.0, c.PD - ETc);
		} else {
			c.S <- max(0.0, c.S - ETc);
		}

		// Biomasse
		float PAR <- alpha_par * sw / 1000.0;
		float LAI <- aB * c.B;
		float fPAR <- max(0.1, 1.0 - exp(-k_LAI * LAI));
	
	
			
		float Topt <- 30.0;
		float Trange <- 8.0;
		float fT <- max(0.0, 1.0 - ((tmean - Topt) / Trange)^2);
		
		float S_opt <- S_max * 0.6;
		float S_wp  <- S_max * 0.2;
		float fW <- (c.PD > 0)
		  ? 1.0
		  : (c.S >= S_opt ? 1.0
		  : (c.S <= S_wp ? 0.0
		  : (c.S - S_wp) / (S_opt - S_wp)));
		
		//float fN <- min(1.0, c.N_avail / 20.0);
		
		// --- Dynamique de l'azote --- //
	//	if (c.lifespan = c.crop_duration * 0.5) { c.N_avail <- c.N_avail + 5.0; }
		/*float Topt <- 29.0;
		float Trange <- 12.0;
		float fT <- max(0.0, 1.0 - abs(tmean - Topt) / Trange);

		float S_opt <- S_max * S_opt_frac;
		float S_wp <- S_max * S_wp_frac;
		float fW <- (c.PD > 0) ? 1.0 : (c.S >= S_opt ? 1.0 : (c.S <= S_wp ? 0.0 : (c.S - S_wp) / (S_opt - S_wp)));
*/
		float fN <- min(1.0, c.N_avail / N_opt);
		float deltaB <- RUE * PAR * fPAR * fT * fW * fN - m_resp * c.B;
		deltaB <- max(deltaB, -0.05 * c.B);
		if ((length(Crop) > 0) and (c =(Crop first_with (each.the_farmer.practice.id = RICE_CF)) )) {
		//	write "CF " + c.name + " " + cycle + " -> " + sample(sw) + " " + sample(c.PD)+ " " + sample(fT) + " " +sample(fW) + " "+ sample(fN)+ " " + sample(PAR)+" " + sample(fPAR) +" "+ sample(RUE) + " "+ sample(deltaB) + sample(c.B);
		}
		if ((length(Crop) > 0) and (c =(Crop first_with (each.the_farmer.practice.id = RICE_AWD)) )) {
		//	write "AWD " +c.name + " " + cycle + " -> " + sample(sw) + " " + sample(c.PD)+ " " + sample(fT) + " " +sample(fW) + " "+ sample(fN)+ " " + sample(PAR)+" " + sample(fPAR) +" "+ sample(RUE) + " "+ sample(deltaB) + sample(c.B);
		}
		c.B <- c.B + deltaB; 

		c.N_avail <- max(0.0, c.N_avail - 0.3 * max(0.0, deltaB));
		//return c.concerned_plot.shape.area * c.the_farmer.practice.Bmax / (1+ exp(-c.the_farmer.practice.k * (c.lifespan - c.the_farmer.practice.t0)));
	}
	bool is_sowing_date (Crop_practice pr, int shift){	
		return (current_date.day_of_year + shift) in pr.sowing_date ;
	}
	bool is_harvesting_date(Crop_practice pr, int shift) {
		return (current_date.day_of_year + shift)  in pr.harvesting_date ;
	}
	
	
}
 
  
// ======================================================================
// ORYZA-BASED MODEL
// ======================================================================
 
species Oryza parent: Plant_growth_model {
	string id <- ORYZA;
	
	map<Crop_practice, bool> need_update ;

	reflex update_practice_data when: not empty(need_update.values collect each){
		loop p over: practices.values {
			if (need_update[p]) {
				do update_data(p);
				need_update[p] <- false;
			}
		}
	}
	int compute_crop_duration(Crop c) {
		return c.the_farmer.practice.current_oryza.key[1] - c.the_farmer.practice.current_oryza.key[0];
	}
			
	action initialize {
		loop p over: data_files_yields.keys {
			Crop_practice pract <- practices[p];
			matrix<string> yieldsP <- matrix(csv_file(data_files_yields[p], true)); 
			matrix<string> dataP <- matrix(csv_file(data_files_practices[p], true)); 
			
			int rs_ <- 1; 
			int rs;
			int r <- 0;
			int de <- -1;
			
			int cy_  ;
			loop i from: 0 to: dataP.rows -1 {
				rs <- int(dataP[0,i]);
				int cy <- int(dataP[1,i]) + 365 * (rs -1) ;
				if (de = -1) {
					de <- cy;
				}
				if (rs > rs_) {
					float y <- float(yieldsP[1,rs_ -1]);
					pract.oryza_data[[de,cy_]] <- y;
					rs_ <- rs;
					de <- cy;
				}
				if (i = dataP.rows -1) {
					float y <- float(yieldsP[1,rs -1]);
					pract.oryza_data[[de,cy]] <- y;	
				}
				cy_ <- cy;
			}
			need_update[pract] <- false;
			do update_data(pract);
			
		}
		
	}
	
	action update_data(Crop_practice pr) {
		if (empty(pr.oryza_data)) {
			ask world {do pause;}
		} else { 
			pr.current_oryza <- first(pr.oryza_data.pairs); 
			remove key: pr.current_oryza.key from: pr.oryza_data;
		}
	}
	
	action day_biomass_growth(Crop c)  {
		c.B <- c.the_farmer.practice.current_oryza.value * c.lifespan / c.crop_duration * c.concerned_plot.shape.area;
	}
	
	float yield_computation (Crop c) {
		need_update[c.the_farmer.practice] <- true;
		return c.B * c.concerned_plot.shape.area / 10000; // kg per ha ?
//		return c.the_farmer.practice.current_oryza.value * c.concerned_plot.shape.area;
	}
	
	bool is_sowing_date (Crop_practice pr, int shift){
		return cycle + shift = pr.current_oryza.key[0];
	}
	
	bool is_harvesting_date(Crop_practice pr, int shift) {
		return cycle + shift = pr.current_oryza.key[1];
		
	}
}