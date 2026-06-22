/**
* Name: WeatherTransformerORYZA
* Based on the internal empty template. 
* Author: patricktaillandier
* Tags: 
*/
model WeatherTransformerORYZA

global {
	
    string input_path <- "../includes/Dong Thap/Weather_Dong_Thap_01_09_2018-31_12_2023.csv";
    string output_path <- "../results/VNDT1.18";

    init {
        // Lecture du fichier brut ligne par ligne
        file input_file <- text_file(input_path);
        list<string> lines <- input_file.contents;

        // Initialisation de l'en-tête ORYZA (Longitude, Latitude, Altitude, A, B)
        string final_output <- "105.63, 10.45, 5, 0, 0\n";

        // Boucle sur les lignes en ignorant l'en-tête du CSV (index 0)
        loop i from: 1 to: length(lines) - 1 {
            string line <- lines[i];
            list<string> parts <- line split_with ";";

            // Vérifier que la ligne contient bien les données attendues
            if (length(parts) >= 11) {
                
                // 1. Extraction et calcul de la date (pour obtenir le DOY - Day Of Year)
                string date_str <- parts[1]; 
                list<string> date_parts <- date_str split_with "-";
                int year <- int(date_parts[0]);
                int month <- int(date_parts[1]);
                int day <- int(date_parts[2]);
                
                // Calcul du jour de l'année (DOY) avec le type 'date' de GAMA
                date my_date <- date([year, month, day]);
                date start_of_year <- date([year, 1, 1]);
                // La différence de dates en GAMA donne des secondes, #day vaut 86400 sec
                int doy <- int((my_date - start_of_year) / #day) + 1;

                // 2. Extraction des variables brutes
                float temp_max <- float(parts[2]);
                float temp_min <- float(parts[3]);
                float temp_avg <- float(parts[4]);
                float humidity <- float(parts[5]);
                float precip <- float(parts[6]);
                float wind_kmh <- float(parts[7]);
                float rad_mj <- float(parts[10]);

                // 3. Transformations mathématiques
                int stn <- 1;
                int rad_kj <- int(rad_mj * 1000); // MJ vers kJ
                float wind_ms <- wind_kmh / 3.6;  // km/h vers m/s

                // Calcul de la pression de vapeur (VP) en kPa
                float es <- 0.6108 * exp((17.27 * temp_avg) / (temp_avg + 237.3));
                float vp <- (humidity / 100.0) * es;

                // 4. Formatage (arrondis pour correspondre au standard)
                vp <- vp with_precision 2;
                wind_ms <- wind_ms with_precision 1;
                temp_min <- temp_min with_precision 1;
                temp_max <- temp_max with_precision 1;
                precip <- precip with_precision 1;

                // 5. Construction de la ligne ORYZA
                string row_str <- "" + stn + "," + year + "," + doy + "," + rad_kj + "," + temp_min + "," + temp_max + "," + vp + "," + wind_ms + "," + precip + "\n";
                
                final_output <- final_output + row_str;
            }
        }

        // Sauvegarde du résultat dans le dossier "results"
        save final_output to: output_path format: "text";
        
        // Affichage dans la console
        write "Transformation terminée avec succès !";
        write "Le fichier VNDT1.18 a été généré dans le dossier 'results'.";
    }
}

experiment RunTransformation type: gui {
    // Cette expérience ne sert qu'à exécuter le bloc 'init' du global
}