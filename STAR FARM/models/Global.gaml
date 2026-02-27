/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

import "Entities/Indicator.gaml"

import "Entities/Cultivar.gaml"

//import "Entities/Parasite.gaml"

import "Entities/Weather.gaml"

import "Entities/Plant growth models.gaml"

import "Entities/Farms and Plots.gaml"

import "Parameters.gaml"

import "Constants.gaml"


global { 
	
	geometry shape <- envelope(plots_shapefile);
	int init_day_of_year <-  current_date.day_of_year;
		
	species<Plot> plot_species <- nil;
	
	bool ready_to_end_season <- false;
	
	float rain_last_days <- 0.0;
	
	bool mode_batch <- false;
   
	bool end_of_sim <- false; 

// Output file paths
    string output_file_day <- "../results/daily_data.csv";
    string output_file_season <- "../results/seasonal_data.csv";
    string output_file_year <- "../results/yearly_data.csv";
    	
    list<Plot> active_plots ;
	list<Farmer> active_farmers ;
		
	
	  // Total provincial capacity (updates automatically based on agent count)
    float max_province_pumping_capacity ;
  
  
	init { 
		do init_action;
		do create_indicators;
		do init_all_headers;
		do load_cultivars;
		do create_practices;
		do create_plant_growth_models;
		do create_plots;	
		do init_weather_data;
		do init_market;
		// compute the surface for each practice at the begining of the simulation
		ask practices {do compute_practice_area;}
		ask remove_duplicates(PG_models){
			do initialize();
		}  
	}
	
	
	
	// -------------------------------------------------------------------------
    // HEADER INITIALIZATION FUNCTIONS
    // -------------------------------------------------------------------------
    
    action init_all_headers {
        if save_results {
			string pr <- string(possible_practices.keys) replace("[","") replace("]","")replace("'","")  ;
			id_xp <- pr + "-" + weather_id +"-"+market_id;
		} 
		output_file_day <- output_folder + "/day/daily_data_" + int(self)+ "_" + id_xp+".csv" ;
		output_file_season <- output_folder + "/season/seasonal_data_" + int(self)+ "_" + id_xp+".csv" ;
		output_file_year <- output_folder + "/year/yearly_data_" + int(self)+ "_" + id_xp+".csv" ;
		
        do write_header_day;
        do write_header_season;
        do write_header_year;
    }
    
	action write_header_day {
        if (save_results and not empty(dayly_indicators)) {
            // Fixed columns
            string header <- "id_sim,year,month,day,seed";
            // Dynamic columns (all daily indicators)
            list<Indicator> daily_inds <- dayly_indicators.values;
            loop ind over: daily_inds { header <- header + "," + ind.name; }
            header <- header + "\n";
            save header to: output_file_day format: "text" rewrite: true;
        }
    }

    action write_header_season {
        if (save_results and not empty(seasonal_indicators)) {
            string header <- "id_sim,year,month,day,seed";
            list<Indicator> seasonal_inds <- seasonal_indicators.values;
            loop ind over: seasonal_inds { header <- header + "," + ind.name; }
           	header <- header + "\n";
            save header to: output_file_season format: "text" rewrite: true;
        }
    }

    action write_header_year {
        if (save_results and not empty(yearly_indicators)) {
            string header <- "id_sim,year,month,day,seed";
            list<Indicator> yearly_inds <- yearly_indicators.values;
            loop ind over: yearly_inds { header <- header + "," + ind.name; }
            header <- header + "\n";
            save header to: output_file_year format: "text" rewrite: true;
        }
    }
	
	action init_action;
	
	
	reflex end_of_days when: cycle > 0 {
		do write_day_report;
	}
	
	reflex end_of_season when: ready_to_end_season and empty(Crop) {
		do write_season_report;
	}
	
	
	reflex end_of_year when: cycle > 1 and current_date.day_of_year =  day_start_of_year{
		do write_year_report;
		ask Farmer {do decide_practice;}
		ask practices {do switch_to_new_year;}
		  // 4. Reset counters (Important: do this AFTER saving)
        ask Farmer { yearly_profit <- 0.0; }
		if use_dynamic_market {
			ask the_market {
				do annual_update;
			}
		}	
	}
	
	
	
	reflex update_end_of_season {
		 ready_to_end_season <- not empty(Crop);
	}
	
	  
    reflex update_rain_memory {
    	rain_last_days <- rain_last_days * rainfall_memory_decay + the_weather.rain; 
    }
    
    
   
   
   // -------------------------------------------------------------------------
    // REPORTING FUNCTIONS (CALCULATE + DISPLAY + SAVE)
    // -------------------------------------------------------------------------

	//for calibration
	action compute_fitness;
	
    // --- DAILY REPORT ---
    action write_day_report {
        list<Indicator> daily_inds <- dayly_indicators.values;
        if (not empty(daily_inds)) {
        		        
	        // 1. Calculate values
	        ask daily_inds { do generic_compute_value; }
	        
	        // 2. Console Display (Grouped by category)
	        if (write_results ) {
	            write "\n=== DAILY REPORT (" + current_date + ") ===";
	            map<string, list<Indicator>> by_cat <- daily_inds group_by each.category;
	            loop cat over: by_cat.keys {
	                write ">>> " + cat;
	                loop ind over: by_cat at cat {
	                    write "   * " + ind.legend + ": " + (ind.value with_precision ind.float_precision) + " " + ind.unit;
	                }
	            }
	        }
	
	        // 3. CSV Save
	        if (save_results) {
	            string row <- "" + int(self) + "," + current_date.year + "," + current_date.month + "," + current_date.day + "," + seed;
	            loop ind over: daily_inds { row <- row + "," + ind.value; }
	            row <- row + "\n";
	            save row to: output_file_day format: "text" rewrite: false; 
	        }
	        
        }
    }

    // --- SEASONAL REPORT ---
    action write_season_report {
        new_season <- false;
		active_plots <- Plot where (each.is_active);
		active_farmers <- Farmer where (each.is_active);
		
        list<Indicator> seasonal_inds <- seasonal_indicators.values;
        if (not empty(seasonal_inds)) {
	        	        
	        // 1. Calculate
	        ask seasonal_inds { do generic_compute_value; }
	
	        // 2. Console Display
	        if (write_results) {
	            write "\n################################################################";
	            write "#        CONSOLIDATED KPI REPORT: SEASON END                   #";
	            write "################################################################";
	            
	            // Tip: Group by automatically recreates your sections (SECTION 1, SECTION 2...)
	            map<string, list<Indicator>> by_cat <- seasonal_inds group_by each.category;
	            
	            loop cat over: by_cat.keys {
	                write "\n>>> " + cat + " <<<";
	                loop ind over: by_cat at cat {
	                    write "   * " + ind.legend + ": " + (ind.value with_precision ind.float_precision) + " " + ind.unit;
	                }
	            }
	            write "\n================================================================";
	        }
	
	        // 3. CSV Save
	        if (save_results) {
	            string row <- "" + int(self) + "," + current_date.year + "," + current_date.month + "," + current_date.day + "," + seed;
	            loop ind over: seasonal_inds { row <- row + "," + ind.value; }
	            row <- row + "\n";
	            save row to: output_file_season format: "text" rewrite: false;
	        }
		}
    }

    // --- YEARLY REPORT ---
    action write_year_report {
        list<Indicator> yearly_inds <- yearly_indicators.values;
		
		if not empty(yearly_inds) {
		// 1. Calculate
	        ask yearly_inds { do generic_compute_value; }
	
	        // 2. Console Display
	        if (write_results) {
	            write "\n################################################################";
	            write "#        YEARLY INDICATORS REPORT                              #";
	            write "################################################################";
	            
	            map<string, list<Indicator>> by_cat <- yearly_inds group_by each.category;
	            
	            loop cat over: by_cat.keys {
	                write "\n>>> " + cat + " <<<";
	                loop ind over: by_cat at cat {
	                    write "   * " + ind.legend + ": " + (ind.value with_precision ind.float_precision) + " " + ind.unit;
	                }
	            }
	            write "\n================================================================";
	        }
	
	        // 3. CSV Save
	        if (save_results) {
	            string row <- "" + int(self) + "," + current_date.year + "," + current_date.month + "," + current_date.day + "," + seed;
	            loop ind over: yearly_inds { row <- row + "," + ind.value; }
	            row <- row + "\n";
	            save row to: output_file_year format: "text" rewrite: false;
	        }
        }
      
    }

    
  
	
	action create_plots {
		if (plot_species = nil) {
			plot_species <- species<Plot>("Plot");
		}
		create plot_species from: plots_shapefile; 
		
		ask plot_species {
			map attributes <- shape.attributes;
			surface_in_ha <- shape.area / 10000;
			if not empty(plots_to_keep) {
				loop att over: plots_to_keep.keys {
					if not(att in attributes.keys) or not(string(attributes[att]) contains plots_to_keep[att]) {
						do die;
					}
				}
			}
			 
			create Farm { 
				plots << myself; 
				create Farmer returns: f{
					my_farm <- myself;
					shape <-  copy(union(myself.plots));
					plot_area <- myself.plots sum_of each.shape.area;
					
				}
				myself.the_farmer <- first(f);
			}
		}
		max_province_pumping_capacity <- infrastructure_capacity_per_plot * length(plot_species);
		ask Farmer {
			do define_neighbors;
		}
	}
	
}

 