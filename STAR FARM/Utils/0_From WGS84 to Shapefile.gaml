/**
* Name: fromWgs84toShapefile
* Based on the internal skeleton template. 
* Author: patricktaillandier
* Tags: 
*/

model fromWgs84toShapefile

global {
	
	csv_file stations_coordinates_csv_file <- csv_file("../includes/General data/stations_coordinates.csv", true);

	shape_file vnm_admin_shape_file <- shape_file("../includes/General data/vnm_admin1.shp");
	geometry shape <- envelope(vnm_admin_shape_file);
	
	init {
		create Station_agent from: stations_coordinates_csv_file {
			if Latitude = 0 {
				do die();
			}
		}
		save Station_agent to: "../includes/General data/stations.shp" attributes:["name"] format: "shp";
	}
}

species Station_agent {
    string name;
    string Station;
    float Latitude;
    float Longitude;
    float current_salinity <- 0.0;
    
    init {
        // GAMA projette automatiquement les coordonnées GPS (Lat/Lon) sur votre carte locale
        location <- to_GAMA_CRS({Longitude,Latitude }, "EPSG:4326").location;
        name <- Station;
    }
    
    aspect default {
        draw circle(500) color: #red;
        draw name color: #black size: 15 at: location + {0, 600};
    }
}

experiment fromWgs84toShapefile type: gui {
	/** Insert here the definition of the input and output of the model */
	output {
		display map {
			species Station_agent;
		}
	}
}
