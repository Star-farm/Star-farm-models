/**
* Name: CleanShapefile
* Based on the internal skeleton template. 
* Author: patricktaillandier
* Tags: 
*/

model GeneratePlotShapefile

global {
	
	float max_dist <- 10.0;
	float min_area <- 500000.0;
	float dist_simp <- 10.0;
	
	bool simple_data_mode <- false;
	int target_num_plots <- 10;
	
	//shape_file lu_dongthap_shape_file <- shape_file("../includes/Dong Thap/2020/lu_dongthap2020.shp");

	shape_file lua_2019_shape_file <- shape_file("../includes/General data/lua_2019.shp");

	string province_choice <- "Dong Thap";
	bool old_province <- false;
	shape_file province_shapefile <- shape_file("../includes/General data/vnm_admin1" + (old_province ? "-old": "")+ ".shp");
	string output <- "../includes/" +  province_choice + (old_province ? " old" : "")+ "/plot_shapefile" +(simple_data_mode ? "_simple" : "")+ ".shp";
	geometry shape <- envelope(lua_2019_shape_file);
	
	init {
		geometry province <- province_shapefile first_with (each.attributes["adm1_name"] = province_choice);
		create plot from: lua_2019_shape_file accumulate (each.geometries) ;
		write "plot created loaded";	
		list<plot> plots <- plot overlapping province;
		ask plot- plots {
			do die();
		}
		write "first filter of plots";	
		
		
		
		list<list<plot>> clusters <- list<list<plot>>(simple_clustering_by_distance(plot, max_dist));
     	write "end of clustering";	
		
        loop cluster over: clusters {
        	if length(cluster) > 1 {
        		ask first(cluster) {
        			shape <- union (cluster collect each.shape);
        		}
        		ask cluster - first(cluster) {
        			do die();
        		}
        	}
        }
        ask plot {
        	if shape.area < min_area {
        		do die();
        	} else {
        		shape <- shape simplification dist_simp;
        	}
        }
        
       if (simple_data_mode) {
       		loop while: length(plot) > target_num_plots {
				plot p <- plot with_min_of (each.shape.area);
				plot p2 <- plot closest_to p;
				ask p {
	        		shape <- p union p2;
	        	}
	        	ask p2 {
	        		do die();
	        	}
			}
		}
		
		write length(plot);
		save plot format: "shp" to: output;
	}

}

species plot {
	rgb color <- rnd_color(255);
	aspect default {
		draw shape color:color border: #black;
	}
}

experiment CleanShapefile_simple type: gui {
	action _init_(){
		create simulation(simple_data_mode: true);
	}
	
	output {
		display current_map {
			species plot;
		}
	}
}


experiment CleanShapefile type: gui {
	output {
		display current_map {
			species plot;
		}
	}
}
