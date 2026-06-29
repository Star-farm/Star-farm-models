model PreProcessSalinity

import "../models/Parameters.gaml"

global {
	 
    // 1. Input files
    
    string folder <- "Tra Vinh old";
   	shape_file bounds_shapefile <- shape_file("../includes/" + folder+ "/plot_shapefile.shp");
	shape_file stations_shapefile <- shape_file("../includes/General data/stations.shp");
    csv_file timeseries_file <- csv_file("../includes/General data/salinity_timeseries.csv", ",",string, false);
	string output <- "../includes/" + folder+ "/salinity_vulnerability_map.tif";

  	float spatial_discretization <- 5000.0; // length of the cell size for the salinity/pollution grid (m)
  

    // Define the world size based on Dong Thap extent
    geometry shape <- envelope(bounds_shapefile);
    float max_influence_radius <- 30000.0; // 30 km max
    float safe_radius <- 10000.0; 
    float salinity_max_threshold ;
    float protection_coefficient <- 1.0;
    

    init {
    	 // A. Create stations
        create Station from: stations_shapefile ;
        matrix timeseries_matrix <- matrix(timeseries_file);
       	write "timeseries_matrix genereted"; 
        // B. Calculate the "Maximum Salinity Capacity" for each station (Historical P90)
        ask Station {
            int col_index <- -1;
            string n <- lower_case(self.name);
           	loop i from: 1 to: timeseries_matrix.columns - 1 {
            	 if (lower_case(string(timeseries_matrix[i, 0])) = n) {
                    col_index <- i; 
                    break;
                }
            }
            if (col_index != -1) {
                float max_salinity <- 0.0;
                loop row from: 1 to: timeseries_matrix.rows - 1 {
                     float val <- float(timeseries_matrix[col_index, row]);
                     if (val > max_salinity) { max_salinity <- val; }
                }
                base_salinity <- max_salinity; 
                
            }
        }
        salinity_max_threshold <- Station max_of each.base_salinity;
  		write "Max salinity per station"; 
       
        ask vuln_grid {
            float sum_inv_dist <- 0.0;
            float interpolated_val <- 0.0;
            float min_dist <- max_influence_radius; // Pour traquer la station la plus proche
             using (topology(world)) {
	            ask Station where ((each distance_to location)  <= max_influence_radius) {
	            float dist <- max(1.0, myself distance_to self);
                if (dist < min_dist) { min_dist <- dist; } // Mémoriser la plus proche
                
                float inv_dist <- 1.0 / (dist ^ 2);
                interpolated_val <- interpolated_val + (self.base_salinity * inv_dist);
                sum_inv_dist <- sum_inv_dist + inv_dist;
	            }
	            
	            if (sum_inv_dist > 0) {
	                // 1. Valeur IDW pure estimée (en g/L)
	                float raw_salinity <- interpolated_val / sum_inv_dist;
	                
	                // 2. NORMALISATION D'ABORD : On plafonne la violence de la source (max 1.0)
	                float normalized_source <- raw_salinity / salinity_max_threshold;
	                normalized_source <- min(normalized_source, 1.0);
	                
	                // 3. DILUTION SPATIALE ENSUITE : Le "Decay Factor" s'applique sur la vulnérabilité normalisée
	                float decay_factor <- 1.0;
	                if (min_dist > safe_radius) {
	                    decay_factor <- 1.0 - ((min_dist - safe_radius) / (max_influence_radius - safe_radius));
	                }
	                
	                // 4. Vulnérabilité finale (0.0 à 1.0) avec un vrai dégradé
	                grid_value <- normalized_source * decay_factor;
	            }
            
            }
        
        
           float val <- 255 * (1.0 - grid_value); 
           color <- rgb(val,val,val);
        
        }
      
        
        

        // D. MAGIC MAP EXPORT!
        save vuln_grid to: output format: "geotiff";
        write "Pre-processing completed! The spatial matrix .asc has been generated.";
    }
}


grid vuln_grid cell_width: spatial_discretization cell_height: spatial_discretization {
    
} 

species Station {
    string name;
    float base_salinity <- 0.0;
     aspect default {
        draw circle(2000) color: rgb(#red, base_salinity/50.0);
        draw name color: #black size: 15 at: location + {0, 600};
    }
}

experiment generate_grid {
	output {
		display map {
			grid vuln_grid border: #black ;
			image "plots" gis: bounds_shapefile color: #blue  transparency: 0.5;
			species Station;
			
		}
	}
}
