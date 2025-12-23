/**
 * ================================================================================================
 * Name: Plant growth models
 * Description:
 *   This model defines the different plant growth models used in the STARFARM simulation.
 *   It provides a global mechanism for initializing and managing crop growth models associated 
 *   with different agricultural practices. 
 *
 *   Two specific submodels are currently implemented:
 *     1. basicModel – A simple generic crop growth model based on climatic and water balance factors.
 *     2. CERES 
 * 
 *   The models are designed to be called by each crop agent to compute daily biomass increments 
 *   and determine key phenological dates (sowing, harvesting, etc.).
 * 
 * Author: Patrick Taillandier
 * Tags: crop growth, irrigation, rice, STARFARM
 *
 * ================================================================================================
 */


model STARFARM 

import "../Parameters.gaml" 

import "../Constants.gaml"

import "Weather.gaml"

 
import "Farms and Plots.gaml"

 
 

// ======================================================================
// GLOBAL DEFINITIONS
// ======================================================================

global {

	//map containing the Plant Grow Model associated to a practice (id of the practice)
	map<string,Plant_growth_model> PG_models;

	
	//action that creates at the initialization of the simulation the different plant growth models
	action create_plant_growth_models {
		map<string,Plant_growth_model> models;
		loop s over: Plant_growth_model.subspecies { 
			create s returns: new_practices;
			Plant_growth_model ct <- Plant_growth_model(first(new_practices));
			models[ct.id] <- ct ;
		}
		loop pract over: plant_grow_models.keys {
			PG_models[pract] <- models[plant_grow_models[pract]];
		}
	}	
}




// ======================================================================
// GENERIC PLANT GROWTH MODEL SPECIES
// ======================================================================

species Plant_growth_model virtual: true{
	string id; // Unique identifier for the model
	
	// Virtual methods to be implemented in derived models
	float yield_computation(Crop c) virtual: true;	
	action day_biomass_growth(Crop c) virtual: true;	

	
	action initialize;
	int compute_crop_duration(Crop c) {
		int start <- current_date.day_of_year;
		int index_start <- c.the_farmer.practice.sowing.implementation_days index_of start;
		int harvesting_date <-  c.the_farmer.practice.harvesting.implementation_days[index_start];
		if (harvesting_date < start) {
			harvesting_date <- harvesting_date + 365;
		}
		return harvesting_date - start; 
	}
	
	
	
	float compute_Ra {
    // constants
    
    	float lat_deg <- CRS_transform(world.location, "4326").location.y;
    
		int doy <- current_date.day_of_year;
	    float PI <- 3.141592653589793;
	    float Gsc <- 0.0820; // MJ m-2 min-1, constante solaire
	
	    // convert latitude to radians
	    float lat_rad <- lat_deg * PI / 180.0;
	
	    // inverse relative distance Earth-Sun
	    float dr <- 1.0 + 0.033 * cos(2.0 * PI / 365.0 * doy);
	
	    // solar declination (radians)
	    float delta <- 0.409 * sin(2.0 * PI / 365.0 * doy - 1.39);
	
	    // sunset hour angle (radians)
	    float tmp <- -tan(lat_rad) * tan(delta);
	    // clamp tmp to [-1,1] to avoid NaN from acos for extreme lat/doy combos
	    if (tmp < -1.0) { tmp <- -1.0; }
	    if (tmp >  1.0) { tmp <-  1.0; }
	    float ws <- acos(tmp);
	
	    // Ra in MJ m-2 day-1
	    return (24.0 * 60.0 / PI) * Gsc * dr * ( ws * sin(lat_rad) * sin(delta) + cos(lat_rad) * cos(delta) * sin(ws) );
	}
	
} 

// ======================================================================
// CERES CROP GROWTH MODEL
// ======================================================================

species ceresModel parent: Plant_growth_model {
	string id <- CERES;
	
   
    // --- STATE VARIABLES
    map<Plot,float> tt;        // thermal time
    map<Plot,int> stage;         // 0=veg, 1=repro, 2=grain fill, 3=mat
    float LAI <- 0.1;

    // --- STATE VARIABLES
    float soil_water_init <- 200.0; //mm
    map<Plot, float> water_stress;  // 0–1
    map<Crop, float> Zr;
    
    // TECHNICAL VARIABLES
    map<Plot, float> last_growth;
	
	// weather
	
	float tmax update: the_weather.temp_max[current_date];
	float tmin update: the_weather.temp_min[current_date];
	float precip update:  the_weather.rainfall[current_date];
	float sw update:  the_weather.solar_radiation[current_date];
	float Ra update:  compute_Ra();
	
	action initialize{
//		ask plot_species {soil_water <- 0.8 * self.theta_fc * my_cultivar.Zr_ini;}
		water_stress <- create_map(list<Plot>(plot_species), list_with(length(plot_species), 1.0)) ;
	}
	
	
	// compute the yield in kg based on grain biomass
	float yield_computation(Crop c){
		return c.grain_biomass * 10 * c.concerned_plot.surface_in_ha ; // g/m² * 10 * ha
	}
	
	// update phenology. Remark: all plots (and crops) share the same variables (temperature,
	// development stage, etc. This makes sense until data (weather...) is made spatially explicit.
	
	action root_growth(Crop c) {
		if (Zr[c] = nil){
			Zr[c] <- my_cultivar.Zr_ini;
		}else{
			Zr[c] <- min(my_cultivar.Zr_max, Zr[c] + 5.0); // 5 mm / jour
		}
	}
	
	
	reflex phenology {
        float Tmean <- (tmax + tmin) / 2;
        float dTT <- max(0, Tmean - Tbase);
        ask plot_species{
        	if (self.associated_crop = nil){
        		myself.tt[self] <- 0.0;
        		myself.stage[self] <- 0;
        	}else{
        		myself.tt[self] <- myself.tt[self] + dTT;
        		if (myself.stage[self] = 0 and myself.tt[self] >= P1) { myself.stage[self] <- 1; }
		        if (myself.stage[self] = 1 and myself.tt[self] >= (P1 + P5)) { myself.stage[self] <- 2; }
		        if (myself.stage[self] = 2 and myself.tt[self] >= (P1 + 2 * P5)) { myself.stage[self] <- 3; }
        	}
        	
        }
    }
    
    // update soil water balance
    // Water balance will be moved out of plant growth (precipitation, drainage)
    
    action soil_water_balance(Crop c)  {
    	Plot p <- c.concerned_plot;

		float inflow;
		
		// ETo (Hargreaves)
		float tmean <- (tmax + tmin) / 2.0;
		float ETo <- 0.0023 * (tmean + 17.8) * sqrt(max(0.0, tmax - tmin)) * Ra;
		
		// --- Irrigation logic
		float FC_mm <- c.concerned_plot.theta_fc * Zr[c];
		float WP_mm <- c.concerned_plot.theta_wp * Zr[c];
		
		
		 if (c.the_farmer.practice.has_practice(AWD)) {
	    	AWD_Irrigating_practice awd <- AWD_Irrigating_practice(c.the_farmer.practice.get_practice(AWD));
	    	  if (p.soil_water < awd.AWD_threshold * FC_mm) {
	            inflow <- precip + awd.irrigation_amount;
	        }
	    	
	    }else{
	       if (p.soil_water < FC_mm) {
	        	inflow <- precip + (FC_mm - p.soil_water);
	        }
	    }
	    
	   
	    // --- Outflows
	    float transpiration <- ETo * water_stress[p];
	    float drainage <- max(0, p.soil_water + inflow - FC_mm);
	
	    // --- Update soil water
	    p.soil_water <- p.soil_water + inflow - transpiration - drainage;
	
	    p.soil_water <- max(WP_mm, min(p.soil_water, FC_mm));
	     
	    
	    // update water stress
	    if (p.soil_water <= WP_mm) {
            water_stress[p] <- 0.0;
        }
        else if (p.soil_water < FC_mm) {
            water_stress[p] <- (p.soil_water - WP_mm) / (FC_mm - WP_mm);
        }
        else {
            water_stress[p] <- 1.0;
        }
    }
    
    float compute_stress(Crop c){
        float N_demand <- compute_N_demand(c);
        float N_uptake <- min(c.concerned_plot.N_avail, N_demand) * c.concerned_plot.N_uptake_eff;
        c.concerned_plot.N_avail <- c.concerned_plot.N_avail - N_uptake;
        c.plant_N <- c.plant_N + N_uptake;
        
        // compute azote stress
        float N_conc;
		float N_stress;
		
		if (c.B <= 1e-6) {
            N_stress <- 1.0;
        } else {
            N_conc <- c.plant_N / c.B; // g/g
            if (N_conc <= my_cultivar.N_min_conc) {
                N_stress <- 0.0;
            } else {
                N_stress <- min(1.0,
                    (N_conc - my_cultivar.N_min_conc) / (my_cultivar.N_max_conc - my_cultivar.N_min_conc)
                );
            }
        }
        return N_stress;
    }
    
    
    // compute the azote demand
    float compute_N_demand(Crop c) {
        float N_opt_CERES <- c.B * my_cultivar.N_max_conc;
        float demand <- max(0, N_opt_CERES - c.plant_N);
        return demand;
    }
	
	
	action day_biomass_growth(Crop c){
		do root_growth(c);
		do soil_water_balance(c);
		float N_stress <- compute_stress(c);

		if (stage[c.concerned_plot] < 3) {
            float IPAR <- Ra * (1 - exp(-k * LAI));
            float stress <- water_stress[c.concerned_plot];
            float dBiomass <- IPAR * RUE * stress;

            c.B <- c.B + dBiomass;

            LAI <- LAI + 0.01 * dBiomass;
            
            do grain_filling(c, dBiomass, stress);
        }
	}
		
	
	
	// =========================================================
    // GRAIN FILLING (HI dynamique)
    // =========================================================
    action grain_filling(Crop c, float daily_growth, float stress) {

        if (stage[c.concerned_plot] >= 2 and stage[c.concerned_plot] < 3) {

            float dGrain_pot <- daily_growth * grain_fill_rate * stress;

            float HI_current <- c.grain_biomass / max(1e-6, c.B);

            if (HI_current < HI_max) {
                float dGrain <- min(
                    dGrain_pot,
                    HI_max * c.B - c.grain_biomass
                );
                c.grain_biomass <- c.grain_biomass + dGrain;
            }
        }
    }
}



// ======================================================================
// BASIC CROP GROWTH MODEL
// ======================================================================


species basicModel parent: Plant_growth_model {
	string id <- BASIC;
	
	float tmax update: the_weather.temp_max[current_date];
	float tmin update: the_weather.temp_min[current_date];
	float precip update:  the_weather.rainfall[current_date];
	float sw update:  the_weather.solar_radiation[current_date];
	float Ra update:  compute_Ra();
		
	
	float yield_computation(Crop c) {
		
		return c.B * c.concerned_plot.surface_in_ha; // kg per ha
	}

	action day_biomass_growth(Crop c) {
		
		float tmean <- (tmax + tmin) / 2.0;

	
		// ETo (Hargreaves)
		float ETo <- 0.0023 * (tmean + 17.8) * sqrt(max(0.0, tmax - tmin)) * Ra;
		// Coeff Kc selon stade
		float frac <- c.lifespan / (c.crop_duration);
		float Kc <- (frac < 0.35) ? 0.9 : (frac < 0.8 ? 1.05 : 0.95);
		float ETc <- Kc * ETo;

		// Gestion irrigation
		float I <- 0.0;
		c.PD <- c.PD + precip;

		if (c.the_farmer.practice.id = RICE_CF) {
			if (c.PD < CF_min_PD) {
				I <- PD_target - c.PD;
				c.PD <- c.PD + I;
			}
		} else { // AWD
			if (c.PD <= 0 and c.S < AWD_WTD_trigger) {
				I <- PD_target - c.PD;
				c.PD <- c.PD + I;
			}
		}
		
		
		if (I > 0) {
			c.irrigation_total <- c.irrigation_total + I;
			c.irrigation_events <- c.irrigation_events + 1;
		}

		// ET -> perte d'eau
		if (c.PD > 0) {
			c.PD <- max(0.0, c.PD - ETc);
		} else {
			c.S <- max(0.0, c.S - ETc);
		}

		// Biomasse
		float PAR <- alpha_par * sw / 1000.0;
		float LAI <- aB * c.B;
		float fPAR <- max(0.1, 1.0 - exp(-k_LAI * LAI));
	
	
			
		float Topt <- 30.0;
		float Trange <- 8.0;
		float fT <- max(0.0, 1.0 - ((tmean - Topt) / Trange)^2);
		
		float S_opt <- S_max * 0.6;
		float S_wp  <- S_max * 0.2;
		float fW <- (c.PD > 0)
		  ? 1.0
		  : (c.S >= S_opt ? 1.0
		  : (c.S <= S_wp ? 0.0
		  : (c.S - S_wp) / (S_opt - S_wp)));
		
	
		float fN <- min(1.0, c.concerned_plot.N_avail / N_opt);
		float deltaB <- RUE * PAR * fPAR * fT * fW * fN - m_resp * c.B;
		deltaB <- max(deltaB, -0.05 * c.B);
	
		c.B <- c.B + deltaB; 

		c.concerned_plot.N_avail <- max(0.0, c.concerned_plot.N_avail - 0.3 * max(0.0, deltaB));
	}	
}
 