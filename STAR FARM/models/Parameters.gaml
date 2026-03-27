/**
* Name: Parameters
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/


model STARFARM

import "Visual_Parameters.gaml"

global {
	float step <- 1 #day;
	
	bool write_results <- true;
	
	bool save_results <- false;
	
	bool write_calibration_result <- false;     
	
	bool save_calibration_results <- false;
   
	int day_start_of_year <- 300;
	
		
	date starting_date <- date([2018,1,1]) add_days (day_start_of_year -1);
   		
	image_file farmer_image <- image_file("../includes/Images/farmer.png");
	
	shape_file plots_shapefile <- shape_file("../includes/Dong Thap/2020/lu_dongthap2020_clean_2016_2023.shp");
	
	bool use_weather_generator <- false;
	string weather_id <- "Optimistic";
	//string weather_folder <- "../includes/weather_generated/Optimistic" ;
	string weather_file <- "../includes/Dong Thap/Weather_Dong_Thap_01_09_2018-31_12_2023.csv" ;
	float default_salinity <- 0.0;
	bool use_dynamic_market <- false;
	string market_id <- "neutral";
  
	
	string innovation_diffusion_model <- NONE; //NONE, NEIGHBORS
	
	float neighbor_distance <- 10.0;
	
	
   
    map<string, float> possible_practices <- [BAU_3S::1.0];
   
	map<string,string> plots_to_keep <- [];
		
	map<string,string> plant_grow_models <-[];
	string default_plant_grow_model <- LUA_MD;
	
	csv_file cultivars_csv_file <- csv_file("../includes/cultivars.csv", true);
	
	string output_folder <- "../../results";
	
	string id_xp ;
     
    bool use_real_data <- false; // use real data for local salinity
    float spatial_discretization <- 5000.0; // length of the cell size for the salinity/pollution grid (m)
   	float local_salinity_coefficient <- 0.1; //coefficient to apply to the local salinity
   	
    // =========================================================
    // 2. ECONOMIC PARAMETERS (Prices and Costs)
    // =========================================================
    float straw_market_price <- 0.02;      // Selling price of rice straw ($/kg)
    float pumping_cost_per_mm <- 0.5;      // Cost of electricity/fuel for pumping ($/mm/ha)
    float fertilizer_unit_price <- 1.3;    // Cost of chemical nitrogen fertilizer ($/kg)
    float pesticide_unit_cost <- 15.0;    // Cost of one pesticide application ($/spray/ha)

    // =========================================================
    // 3. ENVIRONMENTAL & CLIMATE PARAMETERS
    // =========================================================
     
    
    // Pollution and Salinity Dynamics
    float pollution_decay_rate <- 0.9;      // Daily pollution retention (10% natural degradation/day)
    float pollution_diffusion_prop <- 0.1;  // Amount of pollution shared with neighboring cells
    float salinity_diffusion_prop <- 0.1;   // Amount of salt shared with neighboring cells
    float max_geographic_salinity <- 5.0;   // Maximum salinity at the end of the delta gradient (g/L)
    float water_extraction_salt_impact <- 0.00002; // Impact of water pumping on salt intrusion
	float max_pumping_salinity <- 4.0; // Salinity threshold (g/L) above which the farmer refuses to pump water to avoid burning the rice crop
    float drought_water_scarcity_threshold <- 5.0; // If cumulative rainfall over 7 days is < 5 mm, water becomes scarce in the canals
  	
  // --- Water Availability & Rain Memory Logic ---
    float max_water_capacity <- 100.0; //in mm
	float dilution_factor_coefficient <- 0.1; 
  	float lateral_leakage_coefficient <- 0.015;
  	float water_excess_coefficient <- 0.2;
  	float rainfall_memory_decay <- 0.9;    // Factor (0.0-1.0) determining how fast past rainfall is forgotten. 0.85 means 85% of yesterday's rain "memory" is kept.
    float min_rain_for_access <- 1.0;       // Threshold (mm) of accumulated rain memory required to consider canal water easily accessible/abundant.
  // Hydraulic network capacity (tertiary canals) per hectare.
    // 15.0 mm corresponds to a flow rate of ~1.7 l/s/ha, the standard in Dong Thap.
    float infrastructure_capacity_per_plot <- 15.0; 
   
   // =========================================================
    // 4. BIOLOGICAL & CROP MANAGEMENT PARAMETERS
    // =========================================================
    float rue_efficiency_factor <- 0.64; // Correction factor to adjust theoretical RUE to field conditions (0.0 to 1.0)
    float daily_water_loss_mm <- 10.0;     // Sum of evapotranspiration and deep percolation (mm/day)
  	float straw_burn_emission_factor <- 0.0;// 1460.0; // kg CO2-eq emitted per ton of burned straw
   	
  
    float daily_ch4_base <- 2.6;   // Base daily emission for a normal flooded field (kg CH4/ha/day). Simulates root exudates and native soil carbon respiration      
    float ch4_straw_multiplier <- 0.9;// Extra daily CH4 emitted per kg of fresh straw decomposing
    float leftover_straw_decrease_coefficient <- 0.9;
   	float minimum_water_level_for_ch4 <- 10.0;
    float biomass_to_leftover_coeff <- 0.5;
   	// Seeding
   	float seed_density_kg_ha_mechanical <- 80.0; // Seeding density (kg) under mechanical seeding practices  
   	float seed_density_kg_ha_broadcast <- 150.0; // Seeding density (kg) under broadcast seeding practices    
   
    // Irrigation Thresholds
    float water_target_flooded <- 50.0;   // Targeted water depth for irrigation (mm)
    float awd_pumping_threshold <- -150.0; // Soil water depth that triggers pumping in AWD mode (mm)
    
    // Stress Monitoring Thresholds
    float drought_stress_threshold <- -200.0; // Water level below which plant growth stops (mm)
    float flood_stress_threshold <- 125.0;    // Water level triggering submergence stress (mm)
	   
    // Percentage of biomass that rots every day once flood tolerance is exceeded
    float flood_biomass_decay_rate <- 0.01; // 0.10 = 10% loss per extra day
   	float stress_days_flood_continuous_coeff <- 0.5; //coefficient to compute the minimum number of consicutive flood day for biomass decrease
    
    float n_boost_max_factor <- 0.2; //Defines the maximum growth boost achievable through nitrogen saturation. A value of 0.2 means a variety can grow 20% faster than its potential RUE if stock is high.
   
    float n_saturation_threshold <- 1.2 ; //The safety margin of nitrogen required to trigger the boost effect. 1.2 means the stock must be 20% higher than the daily requirement to be considered "optimal".
    
    float fAPAR_phase1 <- 0.2;
    float fAPAR_phase2 <- 0.7;
    float fAPAR_phase3 <- 0.9;
    float fAPAR_phase4 <- 0.85;
    
    // Minimum Biomass Threshold
    // The minimum amount of biomass (g/m²) required for the plant to stay alive.
    // If rotting reduces biomass below this level, the plant collapses completely.
    float min_biomass_survival_threshold <- 50.0;
    // Nitrogen (N) Management
    float n_application_dose <- 40.0;     // Quantity of nitrogen per application (kg/ha)
    float n_late_stage_limit <- 0.8;      // Maximum growth stage for N input (80% of cycle)
    float daily_n_consumption <- 0.8;     // Daily nitrogen uptake by the plant (kg/ha/day)
    
    // Pest and Disease Logic
    float min_k_pest <- 0.5;
    float pest_humidity_limit <- 80.0;    // Humidity threshold for pest infection (%)
    float pest_temp_limit <- 27.0;        // Minimum temperature for pest infection (°C)
    float pest_infection_prob <- 0.8;     // Probability of outbreak if weather conditions are met
    float pest_daily_increment <- 0.03;   // Daily increase in pest load during infection
    float pest_daily_decrease_coeff <- 0.9; 
    int pest_spray_cooldown_days <- 15;    // Minimum required delay between spray treatments (days)
    float pest_pollution_feedback <- 0.05;// Pollution impact on pest resurgence (killing natural predators)
    float pesticide_pollution_add <- 0.2; // Pollution units added to the cell per spray event (ratio plot area / cell area)
    float pest_reduction_fallow <- 0.9; //reduction factor of the pest for Fallow activity;
    // Yield Calibration
    float biomass_to_ton_conv <- 0.01;    // Unit conversion: g/m² to t/ha
    float harvest_moisture_adjust <- 0.86; // Adjustment for 14% commercial moisture content

	float drought_growth_reduction_factor <- 0.5; // Growth multiplier during drought stress (0.5 = 50% reduction)
    float salinity_sensitivity_slope <- 0.2;      // Yield reduction rate per unit of salinity above tolerance (e.g., 0.2 = 20% loss per g/L)
    
    
    float degradation_rate <- 0.005; // Loss of 0.5% potential per cultivation season
    float regeneration_rate <- 0.02; // Gain of 2% per fallow/flood season
    float min_soil_health <- 0.6;   // Soil never drops below 60% of its potential
    
  // Number of days required for the soil to fully decompose the straw safely
    float safe_rest_period <- 30.0; 
    // Defines how much penalty 1 unit of straw generates
    float toxicity_per_straw_unit <- 0.002;
    // =========================================================
    // 5. STRATEGY-SPECIFIC CONSTANTS
    // =========================================================
    // Business As Usual (BAU - Conventional)
    float bau_seed_density <- 150.0;      // Traditional broadcast seeding rate (kg/ha)
    float bau_pesticide_threshold <- 0.20; // Aggressive/Preventive treatment threshold
    float bau_nitrogen_goal <- 110.0;     // High input nitrogen target (kg/ha)
    float pumping_capacity_bau <- 10.0; // mm/jour (Vieilles pompes)
   	float bau_n_trigger_threshold <- 20.0;  // The nitrogen stock level (kg/ha) that triggers fertilization for BAU farmers. High value (15.0) means they fertilize early to avoid any risk of deficiency (insurance behavior). 
	float bau_n_dose_amount <- 50.0 ;// The amount of nitrogen (kg/ha) applied per dose by BAU farmers. High value (50.0) implies bulk application, often leading to leaching/waste. 
	
   
    // Sustainable (1M_HA - Modern)
    float sust_seed_density <- 80.0;      // Precision mechanical seeding rate (kg/ha)
    float sust_pesticide_threshold <- 0.30;// Integrated Pest Management (IPM) threshold
    float sust_nitrogen_goal <- 80.0;      // Precise/Optimized nitrogen target (kg/ha)
    float pumping_capacity_sust <- 20.0; // mm/jour (Station de pompage moderne 1M_HA)
  	float sust_n_trigger_threshold <- 5.0 ;	// The nitrogen stock level (kg/ha) that triggers fertilization for OMRH farmers. Low value (5.0) implies precision timing (Just-in-Time), waiting until the plant truly needs it. */
	float sust_n_dose_amount <- 30.0;// The amount of nitrogen (kg/ha) applied per dose by OMRH farmers. Lower value (30.0) implies split application and higher efficiency. */
	
   
    // Capacité de pompage active (Pompes diesel vs électriques)
   // =========================================================
    // 6. SOCIO-ECONOMIC PARAMETERS (Labor & Mechanization)
    // =========================================================
    float labor_cost_per_hour <- 0.4;//2.5; // Labor cost ($/h) - Rural Vietnam average
   	float harvest_loss_rate <- 0.09;    // 15% loss to rats, lodging, and transport drop
   
    // =========================================================
    // SERVICE COSTS (Technology vs Manual)
    // =========================================================
    
    // Fixed startup cost (Laser Leveling, Smart Sensors) - This is a heavy investment
    float mech_cost_sust_fixed <- 180.0; // $/ha (Increased to be realistic)
    float mech_cost_bau_fixed <- 60.0;  // $/ha (Just basic tillage)

    // Variable cost: DRONE SPRAY SERVICE
    // This is expensive: ~18-20$ per hectare per flight
    float cost_service_drone_spray <- 20.0; 
    
    // Variable cost: MECHANICAL SOWING (Drum Seeder / Machine)
    float cost_service_machine_sowing <- 40.0; // $/ha
   
   // =========================================================
    // LABOR PARAMETERS FOR EVENTS (Hours per event per ha)
    // =========================================================
    
    // Land preparation: repairing bunds (diguettes), clearing canals, leveling mud before sowing
    float labor_land_prep_hours_manual <- 32.0; // ~4 days of hard work per ha
    float labor_land_prep_hours_meca <- 8.0; // ~1 day of hard work per ha
   
    // Manual field maintenance: weeding by hand, picking golden apple snails, rat catching
    float labor_pest_management_hours <- 22.0; // ~3 days spread over the season
    float labor_IMP_pest_management_hours <- 34.0; // IPM -> require more time
     
    // --- SOWING ---
 	//  include seed soaking, incubation (24-48h process), transport, and broadcasting
    float labor_sowing_manual_hours <- 12.0; 
    // Drone/Machine: fast, but still requires bringing seeds to the field and supervision
    float labor_sowing_machine_hours <- 2.0;

    // --- FERTILIZER ---
    // Increased: Includes carrying heavy 50kg sacks across narrow muddy bunds, mixing, and spreading
    float labor_fertilizer_manual_hours <- 6.0; // per application
    float labor_fertilizer_machine_hours <- 1.0; // Supervision and loading

    // --- HARVEST ---
   // 99% cut by machine, BUT farmers must coordinate bags, carry them to boats/trucks, and negotiate
    float labor_harvest_supervision_logistics <- 16.0; // 2 full days of intense logistics per ha
   
     // --- Labor Hours (Time spent per day) ---
   // Farmers walk the field daily to check for leaks, crab holes, and run pumps.
    // AWD requires precise tube reading, opening/closing valves, and synchronized pumping.
    float daily_labor_water_awd <- 1.5; // 1h30 per day for 1ha
    float daily_labor_water_cf <- 1.0;  // 1h00 per day for 1ha (standard daily patrol)
    
   // include mixing toxic chemicals, washing equipment, and walking in deep mud
    float labor_spray_manual_hours <- 8.0; // per application
    float labor_spray_drone_hours <- 1.0;  // Calling the service provider and watching

    
}

