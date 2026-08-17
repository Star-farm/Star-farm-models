/**
* Name: ONNXPolicy
* Description: Fait tourner Starfarm pilote par une politique MAPPO exportee en .onnx, sans
*              Python ni gama-server. Le modele se choisit dans les parametres AVANT de
*              cliquer sur play.
*
*              Le pont MARL (ReinforcementLearning.gaml) reste utilise pour ce qu'il sait
*              faire -- construire l'observation et appliquer une action -- mais la decision
*              est prise ici, par le plugin ONNX, au lieu d'etre demandee a Python.
*
* Prerequis : le plugin gama.plugin.onnx (type `onnx_model`, operateur `onnx_predict`).
* Author: Killian
* Tags: onnx, marl, starfarm
*/

model ONNXPolicy

import "ReinforcementLearning.gaml"


global {

	// ================= calendrier et scenario =================

	// init_action() de ReinforcementLearning.gaml genere la meteo pour start_year..end_year,
	// soit 2025-2050. Sans ces quatre lignes la simulation demarre en 2015 (defaut de
	// Parameters.gaml) : current_date n'est alors dans aucune cle de la serie generee, et le
	// reflex update_weather de Weather.gaml met la simulation en PAUSE a chaque cycle. La
	// simulation n'avance plus que d'un jour par clic sur play, et comme les graphiques ne
	// s'affichent qu'apres la premiere saison (visible: not empty(seasons_str)), toutes les
	// fenetres restent vides. Memes valeurs que l'experience GUI de reference.
	int day_start_of_year <- 300;
	date starting_date <- date([2025,1,1]) add_days 299;
	bool use_weather_generator <- true;
	bool use_dynamic_market <- true;

	// ================= choix du modele (expose en parametre, cf. experience) =================

	string onnx_policy_name <- "Profit" among: [
		"Profit", "Bal-20k", "Bal-100k", "Bal-200k", "Bal-400k", "Pollution",
		"Bal-200k v2", "Bal-20k @DT", "Profit @DT", "Pollution @DT"
	];

	// Le checkpoint final est le choix par defaut. `best_` retient le maximum d'une serie
	// d'evaluations : pertinent quand la courbe est stable (Profit), trompeur quand elle
	// oscille (lambda eleves), ou il designe l'episode le plus chanceux.
	bool onnx_use_best <- false;

	map<string, string> onnx_dirs <- [
		"Profit"::"saved_models_mappo3_peragent",
		"Bal-20k"::"saved_models_mappo3_balanced",
		"Bal-100k"::"saved_models_mappo3_balanced_l100k",
		"Bal-200k"::"saved_models_mappo3_balanced_l200k",
		"Bal-400k"::"saved_models_mappo3_balanced_l400k",
		"Pollution"::"saved_models_mappo3_pollution",
		"Bal-200k v2"::"saved_models_mappo3_l200k_v2",
		"Bal-20k @DT"::"saved_models_mappo3_dtnew_l20k",
		"Profit @DT"::"saved_models_mappo3_dtnew_profit",
		"Pollution @DT"::"saved_models_mappo3_dtnew_pollution"
	];

	onnx_model onnx_policy <- nil;
	bool onnx_ready <- false;
	bool onnx_started <- false;

	// Chemin depuis models/Experiments/ vers rl/<dossier>/<fichier>.onnx
	string onnx_path() {
		return "../../rl/" + onnx_dirs[onnx_policy_name] + "/"
			+ (onnx_use_best ? "best_starfarm_ippo.onnx" : "starfarm_ippo.onnx");
	}

	// ================= chargement =================

	// Charge a la premiere utilisation plutot qu'a la declaration : un fichier manquant
	// donne ici un message lisible, alors qu'une initialisation de variable globale
	// echouerait avant `init` et ne produirait qu'une NPE opaque plus tard.
	action onnx_load() {
		string p <- onnx_path();
		onnx_policy <- onnx_model(p);
		write "Politique ONNX : " + onnx_policy_name + "  ->  " + p;
		write onnx_policy.info;

		// L'export PyTorch declare une entree `obs` de forme [-1,18] et deux sorties,
		// `action_mean` et `action_std`. On ne consomme que la moyenne : en deploiement la
		// decision est deterministe (greedy), l'ecart-type ne sert qu'a l'exploration.
		if (not (onnx_policy.outputs contains "action_mean")) {
			write "ATTENTION : pas de sortie 'action_mean'. Sorties du graphe = "
				+ onnx_policy.outputs;
		}
		onnx_ready <- true;
	}

	// ================= tour de decision =================

	// Un tour par annee, dans un ordre aleatoire, chaque fermier decidant apres avoir vu les
	// engagements des precedents. C'est exactement le protocole d'entrainement : l'observation
	// porte la part de premium deja engagee et la fraction de fermiers ayant deja decide, ce
	// qui permet a une politique PARTAGEE de differencier les fermes. Un ordre fixe, ou des
	// decisions simultanees, feraient s'effondrer le marche premium.
	action onnx_decision_round() {
		if (not onnx_ready) {
			do onnx_load();
		}

		list<string> turn <- shuffle(rl_possible_agents);
		loop a over: turn {
			// Meme vecteur que PetzAgent.observe_one() : 11 valeurs de rl_obs, les 6 de
			// l'action precedente, puis l'avancement dans l'episode. 18 au total.
			list<float> la <- rl_last_action[a];
			if (la = nil) {
				la <- list_with(6, 0.0);
			}
			list<float> obs <- rl_obs(farmer_by_name[a]) + la + [
				float(rl_year_count) / float(rl_max_years)
			];

			// La forme trois-operandes rend le tenseur brut sans passer par la dataframe :
			// une seule sortie a convertir au lieu des deux.
			list<list<float>> out <- onnx_predict(onnx_policy, obs, "action_mean");
			list<float> act <- first(out);

			rl_last_action[a] <- act;
			// apply_rl_action borne chaque composante dans [0,1] : la moyenne brute de
			// l'acteur gaussien n'a pas besoin d'etre ecretee ici.
			do apply_rl_action(farmer_by_name[a], act);
			rl_decided_count <- rl_decided_count + 1;
		}
	}

	// Premier tour : sans lui, la premiere annee tournerait sur les pratiques par defaut.
	reflex onnx_first_round when: not onnx_started {
		do onnx_decision_round();
		onnx_started <- true;
	}

	// Puis un tour a chaque fin d'annee. rl_finalize_year met a jour les compteurs et remet
	// rl_decided_count a zero, donc il doit passer AVANT le tour suivant.
	reflex onnx_year_round when: onnx_started and year_done {
		do rl_finalize_year();
		do onnx_decision_round();
	}

	reflex onnx_end when: rl_year_count >= rl_max_years {
		write "Fin de l'episode : " + rl_max_years + " annees, politique " + onnx_policy_name;
		write "  profit global cumule : " + rl_completed_profit;
		write "  pollution moyenne    : "
			+ (empty(Farmer) ? 0.0 : (Farmer mean_of (rl_farm_pollution(each))));
		do pause();
	}
}


experiment onnx_policy_run type: gui parent: generic_exp {

	parameter "Politique (.onnx)" var: onnx_policy_name category: "Modele";
	parameter "Utiliser le checkpoint best_" var: onnx_use_best category: "Modele";

	parameter "Province" var: province init: DONG_THAP_OLD category: "Carte";
	parameter "Carte simplifiee" var: simple_spatial_data init: true category: "Carte";

	parameter "Nombre d'annees" var: rl_max_years init: 25 category: "Simulation";

	// Meme cablage que l'experience marl : pratiques pilotees par l'action RL, marche
	// reactif, et surtout rl_controlled qui desactive la diffusion aleatoire de fin d'annee
	// -- sans quoi elle ecraserait les decisions de la politique.
	parameter "RL controlled" var: rl_controlled init: true category: "Simulation";
	parameter "Custom practices" var: custom_practices init: true category: "Simulation";
	parameter "Market retroaction" var: add_market_retroaction init: true category: "Simulation";

	output {
		layout horizontal([vertical([3::5000,1::5000])::5000,vertical([2::5000,0::5000])::5000])
			tabs: true editors: false;

		display map axes: false toolbar: false parent: base_map {}
		display farmer_indicators parent: base_farmer_indicators {}
		display environment_indicators parent: base_environment_indicators {}
		display input_indicators parent: base_input_indicators {}

		monitor "Politique" value: onnx_policy_name;
		monitor "Annee" value: rl_year_count;
		monitor "Fermiers ayant decide" value: rl_decided_count;
		monitor "Profit global cumule" value: rl_completed_profit;
		monitor "Pollution moyenne" value:
			empty(Farmer) ? 0.0 : (Farmer mean_of (rl_farm_pollution(each)));
		monitor "Part de premium" value: area_premium_rice_rate();
	}
}
