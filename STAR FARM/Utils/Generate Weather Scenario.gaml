/**
* Name: GenerateWeatherScenario
* Author: Patrick Taillandier
* Tags: 
*/


model WeatherGenerator


global {
    // ================= CONFIGURATION =================
    int start_year <- 2026;
    int end_year <- 2049;
    string output_folder <- "../includes/weather_generated/"; // Output folder
    
    // Baseline parameters for Dong Thap (averages)
    float base_solar_dry <- 18000.0;
    float base_solar_wet <- 13000.0;
    float base_t_min <- 24.0;
    float base_t_max <- 31.0;
    float base_wind <- 2.2;
    float base_salinity <- 0.1; // Eau douce par défaut
   
    // Base historique : Jours 60 à 120 (Mars-Avril)
     int salt_start_doy <- 60;
     int salt_end_doy   <- 120;
     
  init {
        write "Weather Generator";

        // 1. Optimistic
        do generate_scenario("Optimistic", 0.5, 1.0, 1.1, 0.0,0,0);

        // 2. Baseline
        do generate_scenario("Baseline", 1.2, 2.5, 1.25, 0.03,15,10);

        // 3. Pessimistic
        do generate_scenario("Pessimistic", 2.5, 5.0, 1.4, 0.06,30,20);
        
        write "Done. Please check the includes folder.";
    }

    action generate_scenario(string scen_name, float temp_rise_total, float salt_max_intrusion, float rain_intensity_max, float typhoon_probability_max,  int salt_start_doy_coeff, int salt_end_doy_coeff) {
        
        write " -> Scenario processing: " + scen_name;
        
        loop year from: start_year to: end_year {
            
            float progress <- (year - start_year) / (end_year - start_year);
            float current_warming <- temp_rise_total * progress;
            float current_salt_risk <- salt_max_intrusion * progress;
            float current_rain_intensity <- 1.0 + ((rain_intensity_max - 1.0) * progress);
            float current_typhoon_prob <- typhoon_probability_max * progress;

            string filename <- output_folder + scen_name + "/dongthap_" + year + "_" + scen_name + ".csv";
           	date y <- date(year);
         	
            loop doy from: 1 to: date([year]).days_in_year {
            	  bool is_wet_season <- (doy > 120) and (doy < 330);
                
                // 1. TEMPERATURE
                float seasonal_temp <- -1.5 * cos(360 * doy / 365);
                float t_min <- base_t_min + seasonal_temp + current_warming + gauss(0, 0.8);
                float t_max <- base_t_max + seasonal_temp + current_warming + 5.0 + gauss(0, 1.0);
                
                // 2. RAIN & FLOODS
                float rain_amount <- 0.0;
                if (is_wet_season) {
                    if (flip(0.65)) { rain_amount <- abs(gauss(15.0, 10.0)) * current_rain_intensity; }
                    if (flip(current_typhoon_prob)) { rain_amount <- 100.0 + rnd(80.0); }
                } else {
                    if (flip(0.05 * (1.0 - (0.5 * progress)))) { rain_amount <- abs(gauss(5.0, 2.0)); }
                }
                
                // 3. SALINITY
                float salinity <- base_salinity;
                if (doy > (salt_start_doy - int(salt_start_doy_coeff * progress)) and doy < (salt_end_doy + int(salt_end_doy_coeff * progress))) {
                    float daily_salt <- abs(gauss(current_salt_risk, 0.5));
                    if (daily_salt > salinity) { salinity <- daily_salt; }
                    
                }
                if (rain_amount > 10.0) { salinity <- base_salinity; }
                
                // 4. OTHER (Solar, Wind)
                float solar <- is_wet_season ? 13000.0 : 18000.0;
                if (rain_amount > 5.0) { solar <- solar * 0.5; } 
                solar <- solar + gauss(0, 2000);
                float wind <- 2.2 + gauss(0, 0.5);
                
                // 5. HUMIDITY 
                // Baseline: 75% in dry conditions, 85% in wet conditions.
                float humidity <- is_wet_season ? 85.0 : 75.0;
                
                // If it rains, it increases to 90–99%
                if (rain_amount > 0) {
                    humidity <- 90.0 + rnd(9.0);
                } else {
                    // If it is very hot (high t_max), humidity decreases (dry air).
                    if (t_max > 33.0) { humidity <- humidity - 10.0; }
                    humidity <- humidity + gauss(0, 5.0);
                }
                
                // Physical bounds (40% to 100%)
                if (humidity > 100.0) { humidity <- 100.0; }
                if (humidity < 40.0) { humidity <- 40.0; }

               
                salinity <- salinity with_precision 2;
                rain_amount <- rain_amount with_precision 2;
                humidity <- humidity with_precision 2;
                if (rain_amount < 0) { rain_amount <- 0.0; }
				
				// Write the line
                // ID, Year, DOY, Solar, Tmin, Tmax, Wind, Salinity, Rain, Humidity
                string line <- "1," + year + "," + doy + "," + 
                               round(solar) + "," + 
                               t_min with_precision 1 + "," + 
                               t_max with_precision 1 + "," + 
                               wind with_precision 1 + "," + 
                               salinity + "," + 
                               rain_amount + "," +
                               humidity + "\n"; // 
                
             
                save line to: filename format: "text" rewrite: false;
            }
        }
    }
}

experiment GenerateWeather type: gui {
    output {
        display View {
            graphics "Info" {
                draw "Weather Generation Tool" at: {50, 50} color: #black font: font("Arial", 24, #bold);
                draw "Check console for progress..." at: {50, 60} color: #blue;
            }
        }
    }
}