/**
* Name: Global
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

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
	
	string output_file_season;
	string output_file_year;
	
	bool end_of_sim <- false;
	
    
	
	  // Total provincial capacity (updates automatically based on agent count)
    float max_province_pumping_capacity ;
  
  
	init {
		if mode_batch {
			string pr <- string(possible_practices.keys) replace("[","") replace("]","")replace("'","")  ;
			id_xp <- pr + "-" + weather_scenario;
		}
		output_file_season <- output_folder + "/results_season_" + int(self)+ "_" + id_xp+".csv" ;
		
		save "id sim,seed,year,month,day,(CTU 12) Avg Rice Yield (t/ha),Methane emissions (kg CH4/ha),GHG Emission Intensity (kg CH4/kg),AWD Adoption Level (% of area),Water Reliability (< tolerance) (% of plots without salinity stress),Area under climate-resilient varieties (%),Crop Diversification Index (distinct varieties),(CTU 31) Risk Response (Avg Stress Days per plot): Salinity Stress (days),(CTU 31) Risk Response (Avg Stress Days per plot): Drought Stress (days),(CTU 31) Risk Response (Avg Stress Days per plot): Flood Stress (days), (CTU 13) Value of By-products (Straw) ($/ha),(CTU 4) Avg Production Costs ($/ha),(CTU 5) Net Farm Income ($/ha),(CTU 8) Profit Margin (%),Avg Labor Intensity (hours/ha/season),(CTU 19/38) Avg Salinity Exposure (g/l),(CTU 39) Irrigation Water Usage (mm/ha),Avg number of pesticide applications\n"
		format: "text" to: output_file_season rewrite: true;
		
		output_file_year <- output_folder + "/results_year_" + int(self)+ "_" + id_xp+".csv" ;
		
		save "id sim,seed,year,month,day,gini index,Bankruptcy risk(%),Top 20 vs bottom 20 income ratio,Coefficient of variation\n"
		format: "text" to: output_file_year rewrite: true;
		
		do load_cultivars;
		do create_practices;
		do create_plant_growth_models;
		do create_plots;	
		do init_weather_data;
		
		// compute the surface for each practice at the begining of the simulation
		ask practices {do compute_practice_area;}
		ask remove_duplicates(PG_models){
			do initialize();
		}  
	}
	
	reflex end_of_year when: cycle > 1 and current_date.day_of_year =  day_start_of_year{
		do write_year_report;
	}
	
	reflex end_of_season when: ready_to_end_season and empty(Crop) {
		do write_season_report;
	}
	
	reflex update_end_of_season {
		 ready_to_end_season <- not empty(Crop);
	}
	
	// switch to new year, ask the farmers to decide if they change practices, and set a new
	// yearly indicator.
	reflex switch_to_new_year when: cycle > 0 and current_date.day_of_year = init_day_of_year {
		ask Farmer {do decide_practice;}
		ask practices {do switch_to_new_year;}
	}
	
	
	
	  
    reflex update_rain_memory {
    	rain_last_days <- rain_last_days * rainfall_memory_decay + the_weather.rain; 
    }
    
    
    action write_year_report { 
    	list<float> farmer_profit <- (Farmer collect (each.yearly_profit )) sort_by each;
		float gini_index <- gini(farmer_profit);
    	float bankruptcy_risk <- (farmer_profit count (each < 0.0)) / length(Farmer) * 100.0;
    	int number <- round(0.2 * length(Farmer));
		float top_20_vs_bottom_20_income_ratio <- mean(number first farmer_profit) = 0.0 ? 0.0 : (mean(number last farmer_profit) / mean(number first farmer_profit));
		float coefficient_of_variation <- mean(farmer_profit) = 0.0 ? 0.0 : (mean_deviation(farmer_profit)/ mean(farmer_profit));
		ask Farmer {
    		yearly_profit <- 0.0;
    	}
    	if (write_results) { 
    		write "\n################################################################";
		   	write "#        YEARLY INDICATORS    #";
		    write "################################################################\n";
		
			   // =========================================================
			    // SECTION 1: ECONOMIC EQUALITY 
			    // =========================================================
			write "\n>>> SECTION 3: AGRO-ECONOMIC PERFORMANCE <<<";
			write "   * gini index: " + gini_index with_precision 2;
			write "   * Bankruptcy risk: $" + bankruptcy_risk with_precision 1 + "%";
			write "   * Top 20 vs bottom 20 income ratio: " + top_20_vs_bottom_20_income_ratio with_precision 2;
			write "   * Coefficient of variation: " +  coefficient_of_variation with_precision 2 ;
		    write "\n================================================================"; 
    			
    	}
    	if (save_results) {
	  		save "" + int(self)+ "," + seed + "," + current_date.year + "," + current_date.month + "," + current_date.day + ","
		  	+ gini_index +","+bankruptcy_risk +","+top_20_vs_bottom_20_income_ratio +","+coefficient_of_variation + "\n"
		  	format: "text" to: output_file_year rewrite: false;
		}
	  
    }
	action write_season_report { 
		new_season <- false;
		list<Plot> active_plots <- Plot where (each.is_active);
		list<Farmer> active_farmers <- Farmer where (each.is_active);
		
		float avg_yield <- (active_plots mean_of each.final_yield_ton_ha);
	    float total_yield_tons <- (active_plots sum_of each.final_yield_ton_ha);
	    float total_ch4_kg <- (active_plots sum_of each.methane_emissions_kg_ha);
	    float avg_ch4_ha <- (active_plots mean_of each.methane_emissions_kg_ha);
	    float emission_intensity <- total_ch4_kg / max(1.0, total_yield_tons * 1000); // kg CH4 / kg Rice
	    float awd_plots <- (active_farmers where (each.practice.irrigation.name = AWD)) sum_of each.plot_area;
	    float awd_adoption <- (awd_plots / (active_farmers sum_of each.plot_area)) * 100;
	 	int plots_safe_salinity <- active_plots count (each.stress_days_salinity = 0);
	    float safe_water_perc <- (plots_safe_salinity / length(active_plots)) * 100;
	    float plots_adapted <- (active_farmers where each.practice.sowing.type_of_cultivar.is_climate_resilient_variety) sum_of each.plot_area;
	    float adapted_area_perc <- (plots_adapted / (active_farmers sum_of each.plot_area)) * 100;
	    float avg_stress_salinity <- mean(active_plots collect each.stress_days_salinity);
	    float avg_stress_drought <- mean(active_plots collect each.stress_days_drought);
	    float avg_stress_flood <- mean(active_plots collect each.stress_days_flood);
	    float avg_stress_flood_continuous <- mean(active_plots collect each.max_stress_days_flood_continuous);
	    float avg_straw_val <- mean(active_plots collect (each.straw_yield_ton_ha * 1000 * straw_market_price));
	    float avg_cost <- mean(active_farmers collect each.total_costs);
	    float avg_net_profit <- mean(active_farmers collect each.profit_net);
	    float avg_margin <- mean(active_farmers collect (float(each.profit_net) / float(max(1.0, each.revenue)) * 100));
	   	list<string> varieties <- active_farmers collect each.practice.sowing.type_of_cultivar.name;
	    int num_varieties <- length(remove_duplicates(varieties)) ;
	    float avg_labor <- mean(active_farmers collect each.accumulated_labor_hours);
	    float avg_pesticide_count <- mean(active_plots collect each.pesticide_count);
	    float avg_salinity_exp <- mean(active_plots collect each.local_salinity);
	    float avg_water_pumped <- mean(active_plots collect each.total_water_pumped);
	   
	   	if (write_results) { 
		   	write "\n################################################################";
		    write "#        CONSOLIDATED KPI REPORT: MEKONG DELTA TRANSFORMATION    #";
		    write "################################################################\n";
		
		    // =========================================================
		    // SECTION 1: CLIMATE MITIGATION & GHG (Star Farm Focus)
		    // =========================================================
		    write ">>> SECTION 1: CLIMATE MITIGATION & GHG <<<";
		    write "   * Methane emissions (CH4): " + round(avg_ch4_ha) + " kg CH4/ha";
		    write "   * AWD Adoption Level: " + round(awd_adoption) + "% of area";
		    write "   * GHG Emission Intensity: " + (emission_intensity with_precision 3) + " kg CH4/kg rice";
		    
		    // =========================================================
		    // SECTION 2: ADAPTATION & RESILIENCE (Star Farm & CTU 10)
		    // =========================================================
		    write "\n>>> SECTION 2: ADAPTATION & RESILIENCE <<<";
		    
		    // Water & Salinity reliability
		    write "   * Water Reliability (< tolerance): " + round(safe_water_perc) + "% of plots without salinity stress";
		     
		    // Resilience Capacity
		    write "   * Area under climate-resilient varieties: " + round(adapted_area_perc) + "%";
		    
		    write "   * Crop Diversification Index: " + num_varieties + " distinct varieties";
		
		    // Consolidated Stress Days (CTU 31)
		   	write "   * (CTU 31) Risk Response (Avg Stress Days per plot):";
		    write "        - Salinity Stress: " + with_precision(avg_stress_salinity, 2) + " days";
		    write "        - Drought Stress: " + with_precision(avg_stress_drought,2) + " days";
		    write "        - Flood Stress: " + with_precision(avg_stress_flood,2) + " days";
		  	write "        - Max Flood Stress: " + with_precision(avg_stress_flood_continuous,2) + " days";
		
		    // =========================================================
		    // SECTION 3: AGRO-ECONOMIC PERFORMANCE (CTU 2, 3, 4)
		    // =========================================================
		    write "\n>>> SECTION 3: AGRO-ECONOMIC PERFORMANCE <<<";
		    write "   * (CTU 12) Avg Rice Yield: " + with_precision(avg_yield,2) + " t/ha";
		    
		    write "   * (CTU 13) Value of By-products (Straw): $" + round(avg_straw_val) + "/ha";
		
		    
		    write "   * (CTU 4) Avg Production Costs: $" + round(avg_cost) + "/ha";
		    write "   * (CTU 5) Net Farm Income: $" + round(avg_net_profit) + "/ha";
		    write "   * (CTU 8) Profit Margin: " + round(avg_margin) + "%";
		
		    write "   * Avg Labor Intensity: " + round(avg_labor) + " hours/ha/season";
		    
	    	
		    // =========================================================
		    // SECTION 4: RESOURCE USE & SOIL HEALTH (CTU 6, 13)
		    // =========================output_file================
		    write "\n>>> SECTION 4: RESOURCE USE & SOIL HEALTH <<<";
		    write "   * (CTU 19/38) Avg Salinity Exposure: " + with_precision(avg_salinity_exp,3) + " g/l";
		    
		    write "   * (CTU 39) Irrigation Water Usage: " + round(avg_water_pumped) + " mm/ha";
		     write "   *Avg number of pesticide applications: " + round(avg_pesticide_count);
		   
		
		    write "\n================================================================";
	  	}
	  	if (save_results) {
	  		save "" + int(self)+ "," + seed + "," + current_date.year + "," + current_date.month + "," + current_date.day + ","
	  		+ avg_yield +","+avg_ch4_ha +","+emission_intensity +","+awd_adoption
	  		+","+safe_water_perc +","+adapted_area_perc +"," + num_varieties + ","+avg_stress_salinity +","+avg_stress_drought +","+avg_stress_flood +","+avg_straw_val
	  		+","+avg_cost +","+avg_net_profit +","+avg_margin +","+avg_labor +","+avg_salinity_exp +","+avg_water_pumped +"," + avg_pesticide_count+"\n"
	  		format: "text" to: output_file_season rewrite: false;
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

 