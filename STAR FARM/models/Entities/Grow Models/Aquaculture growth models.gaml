/**
* Name: Aquaculture growth models
* Description: Parsimonious biological growth engine for aquaculture species (shrimp, fish).
* Inherits from Plant_growth_model to plug seamlessly into the STARFARM architecture.
* Author: Patrick Taillandier
*/

model STARFARM

import "Grow model.gaml"

import "../Biological Entities/Aqua Species.gaml"
 


species aqua_mdModel parent: Growth_model {
    string id <- AQUA_MD;

    action day_biomass_growth(Crop c) {
        if (not c.is_dead and c.aqua_variety != nil) {
            Aqua_species sp <- c.aqua_variety;
            Plot p <- c.concerned_plot;

            // 1. Phenological / Cycle advancement (Thermal Time)
            float daily_heat <- max(0.0, the_weather.t_mean - sp.t_base);
            c.accumulated_heat <- c.accumulated_heat + daily_heat;
            c.growth_stage <- c.accumulated_heat / sp.tt_maturity;

            // Initialize post-larvae / fingerling biomass on day 1 (e.g., 2.0 g/m² = 20 kg/ha)
            if (c.biomass <= 0.0) {
                c.biomass <- initial_aqua_biomass;
            }

            // 2. Salinity Stress Factor (Trapezoidal response curve)
            p.local_salinity <- p.my_cell.salinity_level;
            float sal <- p.local_salinity;
            float k_salt <- 1.0;

            if (sal < sp.salinity_min or sal > sp.salinity_max) {
                k_salt <- 0.0; // Outside lethal bounds
                p.stress_days_salinity <- p.stress_days_salinity + 1;
            } else if (sal < sp.salinity_opt_min) {
                k_salt <- (sal - sp.salinity_min) / max(0.1, (sp.salinity_opt_min - sp.salinity_min));
                p.stress_days_salinity <- p.stress_days_salinity + 1;
            } else if (sal > sp.salinity_opt_max) {
                k_salt <- 1.0 - ((sal - sp.salinity_opt_max) / max(0.1, (sp.salinity_max - sp.salinity_opt_max)));
                p.stress_days_salinity <- p.stress_days_salinity + 1;
            }

            // 3. Water Depth Stress Factor (Shallow water causes thermal and oxygen stress)
            float k_water <- 1.0;
            if (p.water_level < sp.min_water_level) {
                k_water <- max(0.1, p.water_level / sp.min_water_level);
                p.stress_days_drought <- p.stress_days_drought + 1;
            }

            // 4. Temperature Stress Factor
            float k_temp <- (the_weather.t_mean > sp.t_base) ? min(1.0, (the_weather.t_mean - sp.t_base) / (sp.t_opt - sp.t_base)) : 0.0;

            // 5. Feed / Nutrient Factor (using nitrogen_stock as feed/organic nutrient pool)
            float k_feed <- 1.0;
            if (c.nitrogen_stock > 0.0) {
                k_feed <- 1.0 + aqua_feed_growth_boost;
                c.nitrogen_stock <- max(0.0, c.nitrogen_stock - daily_aqua_feed_consumption);
            }

            // 6. Pesticide Pollution & Disease Mortality
            // High pesticide runoff from neighboring BAU rice plots kills shrimp/fish
            float poll <- p.my_cell.pollution_level;
            float daily_mortality_rate <- base_aqua_mortality_rate + (poll * sp.pollution_sensitivity);

            // Stochastic disease outbreak (e.g., White Spot Syndrome under high temp/salinity stress)
            if (k_salt < 0.5 or k_water < 0.5) {
                if (flip(aqua_disease_prob)) {
                    daily_mortality_rate <- daily_mortality_rate + aqua_disease_mortality_spike;
                }
            }

            // 7. Logistic Biomass Integration
            float density_regulation <- max(0.0, 1.0 - (c.biomass / sp.carrying_capacity));
            float gross_growth <- c.biomass * sp.base_growth_rate * density_regulation * k_salt * k_water * k_temp * k_feed;
            float biomass_loss <- c.biomass * min(1.0, daily_mortality_rate);

            c.biomass <- max(0.0, c.biomass + gross_growth - biomass_loss);

            // 8. Collapse / Lethality check
            if (c.biomass < min_aqua_survival_biomass or poll > lethal_pollution_threshold) {
                c.is_dead <- true;
                c.biomass <- 0.0;
            }
        }
    }
}