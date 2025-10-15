/**
* Name: STARFARM
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model STARFARM

import "../Global.gaml"

import "../Constants.gaml"


global {
	map<string,Crop_practice> practices;
	
	action create_practices {
		loop s over: Crop_practice.subspecies { 
			create s returns: new_practices;
			Crop_practice ct <- Crop_practice(first(new_practices));
			practices[ct.id] <- ct ;
		}
	}	
}


species Crop_practice virtual: true{
	string id; 
	rgb color;
	rgb color_farmer;
	float market_price; // per kg
	float fert_cost;  // per ha
	float seed_cost; // per ha
	float other_cost ;// per ha 
	
	list<int> sowing_date;
	list<int> harvesting_date;
	
	map<int,string> irrigation;
	map<int,float> fertilization;
	
	float Bmax ;
	float Harvest_index;
	float k ;
	int t0;
	
	map<list<int>,float> oryza_data;
	pair<list<int>,float> current_oryza;
	
	
}


species RiceCF parent: Crop_practice {
	string id <- RICE_CF;
	rgb color <- #darkgreen;
	rgb color_farmer <- #red;
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [210,70];
	
	float Bmax <- 14 / 10000 ;
	float k <- 0.075;
	int t0 <- 60;
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	

	float Harvest_index <- 0.45;
	
	map<int,string> irrigation <- [0::CONTINUOUS, 91::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];
	
	
	
}

species RiceAWD parent: Crop_practice {
	string id <- RICE_AWD;
	rgb color <- #lightgreen;
	rgb color_farmer <- #blue;
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [70,210];
	
	float Bmax <- 14 / 10000 ;
	float k <- 0.075;
	int t0 <- 60;
	float market_price <- 6500.0 ; //VND/kg
	float fert_cost <- 400000.0; // VND/per ha
	float seed_cost <- 600000.0; // VND/per ha
	float other_cost <- 300000.0; // VND/per ha 
	
	
	float Harvest_index <- 0.45;
	
	map<int,string> irrigation <- [0::CONTINUOUS, 21::ALTERNATE,81::CONTINUOUS, 90::NO_IRRIGATION];
	map<int,float> fertilization <- [7::40.0, 20::40.0, 50::40.0];
	
	
}