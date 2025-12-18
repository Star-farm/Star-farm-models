/**
* Name: CleanShapefile
* Based on the internal skeleton template. 
* Author: patricktaillandier
* Tags: 
*/

model CleanShapefile

global {
	
	float max_dist <- 10.0;
	float min_area <- 500000.0;
	float dist_simp <- 10.0;
	
	shape_file lu_dongthap_shape_file <- shape_file("../includes/Dong Thap/2020/lu_dongthap2020.shp");

	geometry shape <- envelope(lu_dongthap_shape_file);
	
	init {
		create plot from: lu_dongthap_shape_file  ;
		list<list<plot>> clusters <- list<list<plot>>(simple_clustering_by_distance(plot, max_dist));
        loop cluster over: clusters {
        	if length(cluster) > 1 {
        		ask first(cluster) {
        			shape <- union (cluster collect each.shape);
        		}
        		ask cluster - first(cluster) {
        			do die;
        		}
        	}
        }
        ask plot {
        	if shape.area < min_area {
        		do die;
        	} else {
        		shape <- shape simplification dist_simp;
        	}
        }
		
		write length(plot);
		save plot format: "shp" to: "../includes/Dong Thap/2020/lu_dongthap2020-clean.shp";
	}

}

species plot {
	rgb color <- rnd_color(255);
	aspect default {
		draw shape color:color border: #black;
	}
}

experiment CleanShapefile type: gui {
	output {
		display current_map {
			species plot;
		}
		
		
		/*display init_map {
			graphics "map" {
				loop g over: Dongthap_shape_file {
					draw g color: #yellow border: #black;
				}
			}
		}*/
	}
}
