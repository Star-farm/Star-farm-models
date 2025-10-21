/**
* Name: Plant growth models
* Based on the internal empty template. 
* Author: Patrick Taillandier
* Tags: 
*/


model STARFARM

import "../Parameters.gaml"

import "../Constants.gaml"

import "Weather.gaml"

 
import "Farms and Plots.gaml"

 
 

global {
		
	map<string,Plant_growth_model> PG_models;
	
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
		ask PG_models{
			do initialize();
		} 
	}	
}

species Plant_growth_model virtual: true{
	string id;
	float biomass_computation(Crop c) virtual: true;	
	action biomass_computation_day(Crop c) virtual: true;	
	bool is_sowing_date(Crop_practice pr) virtual: true;
	bool is_harvesting_date(Crop_practice pr) virtual: true;
	
	action initialize;
	int compute_crop_duration(Crop c) {
		return 0;
	}
	
} 

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
	float biomass_computation(Crop c) {
		/*if (flip(0.01) and c.the_farmer.practice.id = RICE_CF ) {
			write sample(cycle) + " " + c.B;
		}*/
		c.B <- c.B * c.concerned_plot.shape.area;
		
		return c.B;
	}

	action biomass_computation_day(Crop c) {
		
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
	bool is_sowing_date (Crop_practice pr){
		return current_date.day_of_year in pr.sowing_date ;
	}
	bool is_harvesting_date(Crop_practice pr) {
		return current_date.day_of_year in pr.harvesting_date ;
	}
	
	
}
 
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
	
	action biomass_computation_day(Crop c) ;
	
	float biomass_computation (Crop c) {
		need_update[c.the_farmer.practice] <- true;
		
		return c.the_farmer.practice.current_oryza.value;
	}
	bool is_sowing_date (Crop_practice pr){
		return cycle = pr.current_oryza.key[0];
	}
	bool is_harvesting_date(Crop_practice pr) {
		return cycle = pr.current_oryza.key[1];
		
	}
}