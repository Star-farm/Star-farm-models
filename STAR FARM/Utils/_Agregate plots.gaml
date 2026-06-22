/**
* Name: agregateplots
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model agregateplots

global {
	
	int target_num_plots <- 10;
	
	shape_file lu_dongthap_shape_file <- shape_file("../includes/Dong Thap/2020/lu_dongthap2020_clean_2016_2023.shp");

	geometry shape <- envelope(lu_dongthap_shape_file);
	
	init {
		create plot from: lu_dongthap_shape_file  ;
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
		
       write length(plot);
		save plot format: "shp" to: "../includes/Dong Thap/2020/lu_dongthap2020-clean-simple.shp";
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
	}
}
