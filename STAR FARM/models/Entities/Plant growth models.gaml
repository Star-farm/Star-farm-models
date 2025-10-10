/**
* Name: PlantGrowthModels
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM
 
import "Farms and Plots.gaml"

 
 

global {
		
	Plant_growth_model PG_model;
	
	action create_plant_growth_models {
		map<string,Plant_growth_model> plant_growth_models;
		loop s over: Plant_growth_model.subspecies { 
			create s returns: new_practices;
			Plant_growth_model ct <- Plant_growth_model(first(new_practices));
			plant_growth_models[ct.id] <- ct ;
		}
		PG_model <- plant_growth_models[plant_grow_model];
		ask PG_model{
			do initialize();
		} 
	}	
}

species Plant_growth_model virtual: true{
	string id;
	float biomass_computation(Crop c) virtual: true;	
	bool is_sowing_date(Crop_practice pr) virtual: true;
	bool is_harvesting_date(Crop_practice pr) virtual: true;
	
	action initialize;
} 

species basicModel parent: Plant_growth_model {
	string id <- BASIC;
	
	float biomass_computation(Crop c) {
		return c.concerned_plot.shape.area * c.the_farmer.practice.Bmax / (1+ exp(-c.the_farmer.practice.k * (c.lifespan - c.the_farmer.practice.t0)));
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