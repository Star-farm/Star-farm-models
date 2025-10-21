/**
* Name: Farms and Plots 
* Description: Core model defining the relationships between farmers, farms, plots, and crops
* within the STARFARM simulation. It represents the decision-making process of farmers
* and the biological and management processes occurring at the plot and crop levels.
* 
* Author: Patrick Taillandier
*/

model STARFARM

// Import external modules containing crop growth models, farming practices, and parameters
import "Plant growth models.gaml"
import "Practices.gaml"
import "../Parameters.gaml"


/**
 * SPECIES Farmer
 * Represents an individual farmer managing one farm and making decisions about practices.
 */
species Farmer {
	Farm my_farm;  // Reference to the farm owned by this farmer
	
	// The current agricultural practice followed by the farmer
	Crop_practice practice <- practices[possible_practices.keys[rnd_choice(possible_practices.values)]];
	
	float money;  // Economic capital of the farmer
	
	// Compute total water usage as the sum of irrigation water applied to all crops
	float water_usage update: my_farm.plots sum_of (each.associated_crop = nil ? 0.0 : each.associated_crop.irrigation_total);
	
	list<Farmer> neighbors;  // List of neighboring farmers (for diffusion of innovations)
	 
	/**
	 * Action: define_neighbors
	 * Defines neighbors based on spatial proximity (distance = 1.0 m).
	 * This allows social interactions and practice diffusion between farmers.
	 */
	action define_neighbors {
		neighbors <- Farmer at_distance 1.0;
	}
	 
	/**
	 * Action: decide_practice
	 * Determines which decision model to use for adopting new practices.
	 * Currently, only the neighbor-based innovation diffusion model is implemented.
	 */
	action decide_practice {
		switch innovation_diffusion_model {
			match NEIGHBORS {
				do innovation_diffusion_neighbors;
			}
		}
	}
	 
	/**
	 * Action: innovation_diffusion_neighbors
	 * Farmers observe their neighbors’ success (measured by money)
	 * and tend to adopt the practices of wealthier farmers in their neighborhood.
	 */
	action innovation_diffusion_neighbors {
		map<string, float> practice_candidates;
		
		// Evaluate each possible practice based on the average income of neighbors using it
		loop p over: possible_practices.keys {
			list<Farmer> p_farmers <- (neighbors + self) where (each.practice.id = p);
			if not empty(p_farmers) {
				practice_candidates[p] <- p_farmers mean_of (each.money);
			} 
		}
		
		// If there are viable candidates, adopt one probabilistically
		if sum(practice_candidates.values) > 0.0 {
			practice <- practices[practice_candidates.keys[rnd_choice(practice_candidates.values)]];
		}
	}
	
	/**
	 * Reflex: change_practices
	 * Each year (on the same calendar day as initialization), farmers reconsider their practice.
	 */
	reflex change_practices when:cycle > 0 and current_date.day_of_year = init_day_of_year {
		do decide_practice;
	} 
	
	aspect default {
		// Each farmer is drawn using an image colored by their current practice
		draw farmer_image size: {50, 50} color: practice.color_farmer;
	}
}


/**
 * SPECIES Farm
 * Represents a set of plots managed by a single farmer.
 */
species Farm { 
	list<Plot> plots;  // All plots belonging to the farm
}


/**
 * SPECIES Plot
 * Represents a unit of land where one crop can be cultivated.
 */
species Plot { 
	Farmer the_farmer;        // The farmer managing this plot
	Crop associated_crop;     // The crop currently growing on the plot (if any)
	
	/**
	 * Reflex: plantGrow
	 * Invokes the crop growth model each day if a crop is present.
	 */
	reflex plantGrow when: associated_crop != nil {
		ask  PG_models[the_farmer.practice.id] {
			do biomass_computation_day(myself.associated_crop);
		}
	}
	
	/**
	 * Reflex: sowing
	 * Checks whether sowing should occur according to the practice calendar
	 * and creates a new crop on the plot if conditions are met.
	 */
	reflex sowing when: PG_models[the_farmer.practice.id].is_sowing_date(the_farmer.practice){
		create Crop with:(the_farmer:the_farmer) {
			myself.associated_crop <- self;
			concerned_plot <- myself;
			crop_duration <- PG_models[the_farmer.practice.id].compute_crop_duration(self);
		} 
	}
	
	/**
	 * Reflex: harvesting
	 * When the harvesting date is reached, the crop’s income is added to the farmer,
	 * and the crop is removed from the plot.
	 */
	reflex harvesting when: PG_models[the_farmer.practice.id].is_harvesting_date(the_farmer.practice){
		the_farmer.money <- associated_crop.income_computation();
		ask associated_crop { 
			do die; 
		} 
		associated_crop <- nil;
	}
	
	aspect default {
		// Visual representation: empty plots are white; cultivated plots take the color of the practice
		draw shape color: associated_crop = nil ? #white : the_farmer.practice.color border: #black;
	}
}


/**
 * SPECIES Crop
 * Represents an individual crop growing on a plot.
 */
species Crop {
	Farmer the_farmer;     // The farmer who owns the crop
	Plot concerned_plot;   // The plot where the crop is located
	int lifespan <- 0 update: lifespan + 1;  // Number of days since sowing
	int crop_duration;     // Expected total duration of the crop cycle
	
	// Biophysical state variables
	string irrigation_mode <- NO_IRRIGATION;
	float B <- 0.0;          // Biomass
	float S <- S_max * 0.9;  // Soil water storage (mm)
	float PD <- PD_target;   // Ponding depth (mm)
	float N_avail <- 2.0;    // Available nitrogen (kg/ha)
	float irrigation_total;  // Cumulative irrigation (mm)
	int irrigation_events;   // Number of irrigation events
	
	/**
	 * Reflex: fertilization
	 * Adds nitrogen to the system on fertilization days defined by the farmer’s practice.
	 */
	reflex fertilization when: lifespan in the_farmer.practice.fertilization.keys {
		float quantity <- the_farmer.practice.fertilization[lifespan];
		N_avail <- N_avail + quantity;
	}
	
	/**
	 * Reflex: change_irrigation
	 * Updates the irrigation mode according to the management schedule.
	 */
	reflex change_irrigation when: lifespan in the_farmer.practice.irrigation.keys {
		irrigation_mode <- the_farmer.practice.irrigation[lifespan];
	} 
	
	/**
	 * Function: income_computation
	 * Computes the economic return of the crop based on its final biomass
	 * and the market price defined by the farmer’s practice.
	 */
	float income_computation {
		return PG_models[the_farmer.practice.id].biomass_computation(self) * 1000.0 * the_farmer.practice.market_price;
	}
}