/**
* Name: ReinforcementLearning
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/


model ReinforcementLearning


import "Generic Experiment.experiment"  


global {
	action define_farmer_pratices() {
		ask Farmer {
			if flip(0.5) {
				string pract <- practice.irrigation.name;
				practice.other_practices >> pract;
				ask practice.irrigation {
					do die();
				}
				if (pract = CF) {
					ask myself {
						do add_AWD_practice(myself.practice);	
					}	
				} else {
					ask myself {
						do add_CF_practice(myself.practice);	
					}	
				}
			}
		}
	}
}

experiment ReinforcementLearning title: "Reinforcement Learning" type:gui parent: generic_exp {	

	action _init_() {
		create AbstractStarFarm_model (simple_spatial_data:true, custom_practices: true, add_market_retroaction: true);
	}
	
	output {		
		layout horizontal([vertical([3::5000,1::5000])::5000,vertical([2::5000,0::5000])::5000]) tabs:true editors: false;
		display map axes: false toolbar: false parent: base_map{}
		display farmer_indicators parent:base_farmer_indicators {}
		display environment_indicators parent:base_environment_indicators {}
		display input_indicators parent:base_input_indicators {}	
	} 
}



