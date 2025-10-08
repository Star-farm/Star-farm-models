/**
* Name: CropType
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model CropType


global {
	map<string,Crop_type> Crop_types;
	
	action create_crop_type {
		loop s over: Crop_type.subspecies { 
			create s returns: new_crop_type;
			Crop_type ct <- Crop_type(first(new_crop_type));
			Crop_types[ct.id] <- ct ;
		}
			
	}	
}


species Crop_type {
	string id; 
	rgb color;
	float current_price;
	list<int> sowing_date;
	list<int> harvesting_date;
	
	float Bmax ;
	float Harvest_index;
	float k ;
	int t0;
	
}

species Rice parent: Crop_type {
	string id <- "Rice";
	rgb color <- #green;
	list<int> sowing_date <- [120, 300];
	list<int> harvesting_date <- [70,210];
	
	float Bmax <- 14 / 10000 ;
	float k <- 0.075;
	int t0 <- 60;
	float current_price <- 9000.0 ; //VND/kg
	
	
	float Harvest_index <- 0.45;
}

