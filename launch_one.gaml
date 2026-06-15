
import "Star-farm-models/STAR FARM/models/Global.gaml"

experiment calibration_launch type: batch until: end_of_sim repeat: 1 {
    parameter rue_efficiency_factor var: rue_efficiency_factor;
    parameter pest_infection_prob var: pest_infection_prob;
    
    init {
        possible_practices <- [BAU_3S::1.0];
        starting_date <- date([2015,1,1]) add_days (day_start_of_year -1);
        write "Simulation started with RUE: " + rue_efficiency_factor;
    }
}
