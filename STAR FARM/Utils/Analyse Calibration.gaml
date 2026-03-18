/**
* Name: AnalyseCalibration
* Based on the internal skeleton template. 
* Author: patricktaillandier
* Tags: 
*/

model AnalyseCalibration

global {
	csv_file calibration_result_csv_file <- csv_file("../models/Experiments/Calibration/PSO_calibration_result.csv", ",", false);
	map<list<float>,list<float>> solutions;
	int min_parameter_index <- 2;
	int max_parameter_index <- 7;
	 init {
	 	int num_parameters <- max_parameter_index - min_parameter_index + 1;
	 	matrix mat <- matrix(csv_file(calibration_result_csv_file));
	 	loop i from:1 to: mat.rows -1 {
	 		
	 		list<float> sol <- [];
	 		loop j from: min_parameter_index to: max_parameter_index {
	 			sol << float(mat[j,i]);
	 		}
	 		
	 		if (sol in solutions.keys) {
	 			solutions[sol] << float(mat[max_parameter_index+4,i]);
	 		} else {
	 			solutions[sol] <- [float(mat[max_parameter_index+4,i])];
	 		}
	 	}
	 	list<float> best_sol;
	 	float best_fitness <- #max_float;

	 	loop sol over: solutions.keys {
	 		float m_f <- mean(solutions[sol]);
	 		if m_f < best_fitness {
	 			best_fitness <- m_f;
	 			best_sol <- sol;
	 		}
	 	}
	 	
	 	write "BEST SOLUTION : " + best_fitness + "\n";
	 	loop i from: 0 to: num_parameters -1 {
	 		write "" + mat[min_parameter_index+i,0] + " -> " + best_sol[i] + "\n";
	 	}
	 }
}

experiment AnalyseCalibration type: gui {
	/** Insert here the definition of the input and output of the model */
	output {
	}
}
