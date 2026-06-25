/**
* Name: ReinforcementLearning
* Description: MARL entry point for Starfarm. Combines the colleague's clean practice-change
*   actions (change_irrigation / change_pesticide_management / change_input_usage / ...) with
*   the embedded MARL bridge (PetzAgent species + Box(4) action space) driven over gama-server.
*   The RL layer maps a continuous Box(4) action to the colleague's regime-switch functions.
* Author: patricktaillandier (practice actions) + RL bridge
* Tags:
*/


model ReinforcementLearning


import "Generic Experiment.experiment"


global {
	
	 
	int start_year <- 2025;
    int end_year <- 2050;
    string OPTIMISTIC <- "Optimistic" ; 
    string BASELINE <- "Baseline" ;
    string PESSIMISTIC <- "Pessimistic";
     
    string STANDARD <- "Standard";
    string RESOURCE_CRISIS <- "Crisis"; 
     
      
	string weather_scenario <- PESSIMISTIC among: [OPTIMISTIC, PESSIMISTIC]   ;
	string market_scenario <- RESOURCE_CRISIS among: [STANDARD, RESOURCE_CRISIS]   ;
	
	action init_action() {
		switch weather_scenario {
			match OPTIMISTIC {
				// el_nino_salinity_modifier <- 1.5; // Minor salinity increase
				do generate_scenario(OPTIMISTIC,start_year, end_year, 0.5, 1.0, 1.2, 0.0,0,0,prob_el_nino,prob_la_nina,el_nino_temp_offset,el_nino_rain_modifier);
			}
			
			match PESSIMISTIC{
		
              	do generate_scenario(PESSIMISTIC,start_year, end_year, 2.5, 4.5, 1.6, 0.06,30,20,0.35,0.15,0.5,2.0);
			}
		} 
		
		switch market_scenario {
			match STANDARD {
				create Market { 
           			market_id <- "Standard";
            		// Setup: We leave specific trends at 0.0 (neutral)
            		// We set high correlation (0.8) with the global economy
            		corr_water <- 0.8; trend_water <- 0.0;
            		corr_fertilizer <- 0.9; trend_fertilizer <- 0.0; // Follows oil/gas prices
            		the_market <- self;
        		}
			}
			match RESOURCE_CRISIS {
				create Market {
           			market_id <- "Resource-Crisis";
           			
		            // WATER: Becomes expensive (+5% per year ON TOP of inflation) and uncorrelated (0.2)
		            corr_water <- 0.2; 
		            trend_water <- 0.05; 
		            volatility_water <- 0.15; // Very unstable (random droughts)
		
		            // FERTILIZERS: Carbon taxes or shortages (+4% per year)
		            corr_fertilizer <- 0.5;
		            trend_fertilizer <- 0.04;
		
		            // MECHANIZATION: Becomes cheaper (technical progress / efficiency)
		            corr_mech <- 0.5;
		            trend_mech <- -0.01;
		            
		            the_market <- self;
        		}
			}
		}
		ask the_market {
			do generate_data(start_year,end_year);
		}	
	}
	
		


	// ======================================================================
	// PRACTICE-CHANGE ACTIONS (from colleague's commit) — switch a farmer's
	// strategy between well-defined regimes, rebuilding the per-season maps.
	// ======================================================================

	action change_irrigation(Farmer f, bool to_awd) {
		ask f {
			string pract <- practice.irrigation.name;
			if (pract = CF) and to_awd{
				ask practice.irrigation {do die();}
				ask myself {
					do add_AWD_practice(myself.practice);
				}
			} else if (pract != CF) and  not to_awd{
				ask practice.irrigation {do die();}
				ask myself {
					do add_CF_practice(myself.practice);
				}
			}
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : PESTICIDE MANAGEMENT CHANGE (BAU vs IPM)
	// ----------------------------------------------------------------------
	action change_pesticide_management(Farmer f, bool use_IPM) {
		ask f {
			// 1. Find and remove the old pesticide practice
			list<Pesticide_application_practice> pp <- practice.other_practices of_species Pesticide_application_practice;
			practice.other_practices <- practice.other_practices - pp;
			ask pp { do die(); }

			// 2. Define the new thresholds based on the global variables
			map<int,float> pta;
			bool is_three_seasons <- length(practice.sowing.implementation_days) = 3;

			float base_pest_threshold <- use_IPM ? sust_pesticide_threshold : bau_pesticide_threshold;

			if (is_three_seasons) {
				loop i from: 0 to: length(three_seasons_sowing) - 1 {
					pta[three_seasons_sowing.keys[i]] <- base_pest_threshold * pesticide_thresholds_3_seasons[i];
				}
			} else {
				loop i from: 0 to: length(two_seasons_sowing) - 1 {
					pta[two_seasons_sowing.keys[i]] <- base_pest_threshold * pesticide_thresholds_2_seasons[i];
				}
			}

			// Apply the new practice
			ask world { do add_pesticide_practice(myself.practice, pta, use_IPM, use_IPM); }
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : INPUT/FERTILIZER USAGE CHANGE (BAU vs Sustainable)
	// ----------------------------------------------------------------------
	action change_input_usage(Farmer f, bool use_sustainable) {
		ask f {
			// 1. Find and remove the old input practice
			list<Input_use_practice> ip <- practice.other_practices of_species Input_use_practice;
			practice.other_practices <- practice.other_practices - ip;
			ask ip { do die(); }

			map<int,float> ftr;
			map<int,float> fta;
			bool is_three_seasons <- length(practice.sowing.implementation_days) = 3;

			float base_trigger <- use_sustainable ? sust_n_trigger_threshold : bau_n_trigger_threshold;
			float base_target <- use_sustainable ? sust_nitrogen_goal : bau_nitrogen_goal;
			float dose_amount <- use_sustainable ? sust_n_dose_amount : bau_n_dose_amount;

			if (is_three_seasons) {
				loop i from: 0 to: length(three_seasons_sowing) - 1 {
					ftr[three_seasons_sowing.keys[i]] <- base_trigger * fert_trigger_thresholds_coeff_3_seasons[i];
					fta[three_seasons_sowing.keys[i]] <- base_target * fert_targets_coeff_3_seasons[i];
				}
			} else {
				loop i from: 0 to: length(two_seasons_sowing) - 1 {
					ftr[two_seasons_sowing.keys[i]] <- base_trigger * fert_trigger_thresholds_coeff_2_seasons[i];
					fta[two_seasons_sowing.keys[i]] <- base_target * fert_targets_coeff_2_seasons[i];
				}
			}

			ask world { do add_input_use_practice(myself.practice, ftr, dose_amount, fta, use_sustainable); }
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : RICE CULTIVAR CHANGE (Premium/ST25 vs Standard/OM5451)
	// ----------------------------------------------------------------------
	action change_rice_cultivar(Farmer f, bool is_premium) {
		ask f {
			if (is_premium and (practice.sowing.type_of_cultivar.name != ST25) ){
				practice.sowing.type_of_cultivar <- Cultivar first_with (each.name = ST25);
				practice.sowing.mechanical_seeding <- true;
				practice.sowing.labor <- labor_sowing_machine_hours + labor_land_prep_hours_meca;
			} else if (not is_premium and (practice.sowing.type_of_cultivar.name = ST25) ){
				practice.sowing.type_of_cultivar <- Cultivar first_with (each.name = OM5451);
				practice.sowing.mechanical_seeding <- false;
				practice.sowing.labor <- labor_sowing_manual_hours + labor_land_prep_hours_manual;
			}
		}
	}

	// ----------------------------------------------------------------------
	// ACTION : CALENDAR / SEASONS CHANGE
	// ----------------------------------------------------------------------
	action change_number_seasons (Farmer f, bool three_seasons) {

		// 1. Memorize current pesticide and input states
		bool is_sust_input <- false;
		bool is_ipm_pest <- false;

		ask f.practice {
			list<Input_use_practice> ip <- other_practices of_species Input_use_practice;
			if not empty(ip) { is_sust_input <- first(ip).base_dose = sust_n_dose_amount; }

			list<Pesticide_application_practice> pp <- other_practices of_species Pesticide_application_practice;
			if not empty(pp) { is_ipm_pest <- first(pp).mechanical; }

			// 2. Change the calendar and fallow practice
			if length(sowing.implementation_days) = 2 and three_seasons{
				sowing.implementation_days <- three_seasons_sowing;
				list<Fallow_practice> fp <- other_practices of_species Fallow_practice;
				other_practices <- other_practices - fp;
				ask fp { do die(); }
		 	} else if length(sowing.implementation_days) = 3 and not three_seasons{
				sowing.implementation_days <- two_seasons_sowing;
				ask world { do add_fallow_practice(myself, fallow_day); }
		 	}
		}

		// 3. Force update of related practices so their maps align with the new calendar
		do change_input_usage(f, is_sust_input);
		do change_pesticide_management(f, is_ipm_pest);
	}
	
	
	float area_premium_rice_rate() {
		
		list<Farmer> farmer_premium <- Farmer where (each.practice.sowing.type_of_cultivar.name = ST25);
		if (empty(farmer_premium)) {
			return 0.0;
		}
		
		return (farmer_premium accumulate (each.my_farm.plots)) sum_of (each.shape.area) / sum(Plot collect each.shape.area);
		
	}
	

	// Random year-end practice flip — used by Global.gaml's end_of_year reflex when the
	// run is NOT rl_controlled (baseline diffusion behaviour).
	action define_farmer_pratices() {
		ask Farmer {
			//possible observations (in addition to the current used ones)
			write string(current_date) + " -> "+ name +" - " +
			sample(world.area_premium_rice_rate()) + ", " +
			sample(my_farm.plots mean_of (each.my_cell.pollution_level))+ ", " +
			sample(my_farm.plots mean_of (each.my_cell.salinity_level))
			
			;	 
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

	action init_market() {
		if (the_market = nil) {
			create Market {
				the_market <- self;
				ask Cultivar where (each.name = ST25) {
					myself.floor_price_cultivar <- Cultivar first_with (each.name = OM5451);
					myself.market_saturation_threshold[self] <- 900000;
					myself.price_sensitivity_k[self] <- 1.5;
				}
			}
		}
		// Build the MARL bridge here (not in an init block): Global.gaml's init calls
		// init_market() AFTER create_plots(), so the Farmers already exist. The derived (RL)
		// init_market overrides the base one, so this hook only runs for the RL model.
		if (rl_controlled) {
			do init_petz();
		}
	}

	// ======================================================================
	// MARL BRIDGE (embedded PetzAgent, no co-model). One gama-server step == one
	// simulated DAY; the Python env (StarfarmParallelEnv) macro-steps a full crop
	// year, then calls publish_rl to snapshot the transition.
	// ======================================================================

	// name -> inner Farmer agent (stable identifiers shared with Python).
	map<string, Farmer> farmer_by_name;
	// Stable agent ids.
	list<string> rl_possible_agents;
	// Last action applied per farmer (4 continuous floats, for the observation vector).
	map<string, list<float>> rl_last_action;
	// Episode bookkeeping.
	int rl_year_count <- 0;
	// Longer horizon (25 years). The colleague's scenario data spans 2025-2050, so 25 is the
	// safe maximum; going higher would step past the generated weather/market series.
	int rl_max_years <- 25;
	// --- Sub-step (seasonal) reward tracking. Decisions stay ANNUAL; the Python env can
	// advance in sub-steps of ~a season and read the PROFIT DELTA accrued in each window,
	// densifying the credit-assignment signal at zero extra simulation cost. ---
	// Cumulative profit of all COMPLETED years (in-progress year lives in Farmer.yearly_profit,
	// which Global.gaml resets at end_of_year after snapshotting last_year_global_profit).
	float rl_completed_profit <- 0.0;
	// Cumulative profit already reported to Python (global + per farmer).
	float rl_prev_cum_profit <- 0.0;
	map<string, float> rl_completed_profit_f;
	map<string, float> rl_prev_cum_f;
	// 11 state features + 6 last-action floats + 1 normalised year index.
	int rl_obs_dim <- 18;
	int rl_act_dim <- 6;
	// Sequential decision round: number of farmers that have already committed their action
	// for the CURRENT year. Exposed in the observation as a fraction so a later decider can
	// interpret the (dynamic) premium-share signal: "30% premium with 2/10 decided" reads
	// very differently from "30% with 9/10 decided". Reset at each year boundary.
	int rl_decided_count <- 0;
	// Reward mode: false = shared global reward (project objective); true = per-farmer profit.
	// Set from Python via PetzAgent[0].set_reward_mode(...) after each reset.
	int rl_reward_mode <- 0;        // 0=global profit, 1=per-farm profit, 2=min pollution, 3=balanced
	float rl_balance_weight <- 1.0; // lambda for mode 3: reward = profit_delta - lambda * pollution

	// Apply one farmer's yearly decision — a continuous Box(6) action, each dim in [0,1] —
	// by driving the colleague's regime-switch functions:
	//   act[0] irrigation selector : < 0.5 -> CF, >= 0.5 -> AWD          (change_irrigation)
	//   act[1] irrigation quantity : CF flood depth [30,70] mm / AWD trigger [-50,-250] mm
	//   act[2] pesticide regime    : >= 0.5 -> IPM, else BAU             (change_pesticide_management)
	//   act[3] fertilizer regime   : >= 0.5 -> sustainable, else BAU     (change_input_usage)
	//   act[4] cultivar            : >= 0.5 -> premium (ST25), else standard (OM5451)  (change_rice_cultivar)
	//   act[5] seasons             : >= 0.5 -> three seasons, else two   (change_number_seasons)
	action apply_rl_action(Farmer f, list<float> act) {
		float a_sel <- min(1.0, max(0.0, float(act[0])));
		float a_qty <- min(1.0, max(0.0, float(act[1])));
		float a_pst <- min(1.0, max(0.0, float(act[2])));
		float a_fer <- min(1.0, max(0.0, float(act[3])));
		float a_cul <- min(1.0, max(0.0, float(act[4])));
		float a_sea <- min(1.0, max(0.0, float(act[5])));

		// 1. Season count FIRST: change_number_seasons rewrites the per-season pesticide/input
		//    maps to match the new calendar, so the explicit regime calls must come after it.
		do change_number_seasons(f, a_sea >= 0.5);

		// 2. Pesticide & fertilizer regimes (BAU vs IPM / sustainable).
		do change_pesticide_management(f, a_pst >= 0.5);
		do change_input_usage(f, a_fer >= 0.5);

		// 3. Cultivar (premium ST25 vs standard OM5451).
		do change_rice_cultivar(f, a_cul >= 0.5);

		// 4. Irrigation selector + per-instance quantity knob.
		bool to_awd <- a_sel >= 0.5;
		do change_irrigation(f, to_awd);
		if (to_awd) {
			AWD_Irrigating_practice aw <- AWD_Irrigating_practice(f.practice.irrigation);
			aw.awd_threshold_mm <- -50.0 - 200.0 * a_qty;      // dryness trigger [-50,-250] mm
		} else {
			CF_Irrigating_practice cf <- CF_Irrigating_practice(f.practice.irrigation);
			cf.cf_water_target <- 30.0 + 40.0 * a_qty;          // flood depth [30,70] mm
		}

		// 5. The change_* functions swap practices in `other_practices` but DON'T refresh the
		// `practices_id` cache that has_practice/get_practice read (and change_irrigation kills
		// the old irrigation without removing it from the list). Without this, the next sowing
		// reads a DEAD pesticide/input practice ("target agent is dead"). Purge dead refs and
		// rebuild the cache once, after all the regime switches.
		ask f.practice {
			other_practices <- other_practices where (each != nil and not dead(each));
			do initialize();
		}
	}

	// Per-farmer observation: 11 state features = 4 local farm + 2 local environment +
	// 2 static farm descriptors + 2 GLOBAL market signals + 1 decision-round progress.
	// publish appends the 6 last-action floats and the normalised year index -> 18 floats
	// total. The static descriptors let the SHARED actor specialize per farm; the global
	// signals let the AI perceive market saturation / coupling; the decision-round fraction
	// lets a deterministic shared policy DIVERSIFY (threshold rule on the dynamic premium
	// share seen during the sequential decision round).
	list<float> rl_obs(Farmer f) {
		list<Plot> ps <- f.my_farm.plots;
		Cultivar premium <- Cultivar first_with (each.name = ST25);
		return [
			// --- local farm state ---
			f.last_yearly_profit,
			empty(ps) ? 0.0 : (ps mean_of (each.total_fertilizer_applied)),
			empty(ps) ? 0.0 : (ps mean_of (each.soil_health)),
			empty(ps) ? 0.0 : (ps mean_of (each.final_yield_ton_ha)),
			// --- local environment ---
			empty(ps) ? 0.0 : (ps mean_of (each.my_cell.pollution_level)),
			empty(ps) ? 0.0 : (ps mean_of (each.my_cell.salinity_level)),
			// --- static farm descriptors (shared-actor specialization) ---
			float(length(ps)),
			empty(ps) ? 0.0 : (ps sum_of (each.shape.area)) / 10000.0,
			// --- GLOBAL market signals (identical for all farmers) ---
			// Premium share is DYNAMIC during the sequential decision round: it already
			// reflects the commitments of the farmers that decided earlier this year.
			area_premium_rice_rate(),
			(the_market = nil or premium = nil) ? 1.0 : the_market.r_for_crop(premium),
			// --- decision-round progress: fraction of farmers already committed this year ---
			empty(rl_possible_agents) ? 0.0 : float(rl_decided_count) / float(length(rl_possible_agents))
		];
	}

	// Mean pollution level across a farmer's plots (used by the pollution / balanced rewards).
	float rl_farm_pollution(Farmer f) {
		list<Plot> ps <- f.my_farm.plots;
		return empty(ps) ? 0.0 : (ps mean_of (each.my_cell.pollution_level));
	}

	// Build the PetzAgent bridge once the world (farmers included) is initialised.
	action init_petz() {
		rl_possible_agents <- Farmer collect (string(each));
		loop f over: Farmer {
			farmer_by_name[string(f)] <- f;
			rl_last_action[string(f)] <- list_with(rl_act_dim, 0.0);
			rl_completed_profit_f[string(f)] <- 0.0;
			rl_prev_cum_f[string(f)] <- 0.0;
		}
		create PetzAgent {
			agents <- copy(myself.rl_possible_agents);
			possible_agents <- copy(myself.rl_possible_agents);
			observation_spaces <- possible_agents as_map (each::[
				"type"::"Box",
				"low"::list_with(myself.rl_obs_dim, -1000000000.0),
				"high"::list_with(myself.rl_obs_dim, 1000000000.0),
				"shape"::[myself.rl_obs_dim],
				"dtype"::"float"
			]);
			action_spaces <- possible_agents as_map (each::[
				"type"::"Box",
				"low"::list_with(myself.rl_act_dim, 0.0),
				"high"::list_with(myself.rl_act_dim, 1.0),
				"shape"::[myself.rl_act_dim],
				"dtype"::"float"
			]);
			loop a over: possible_agents {
				observations[a] <- list_with(myself.rl_obs_dim, 0.0);
				rewards[a] <- 0.0;
				terminations[a] <- false;
				truncations[a] <- false;
				infos << a::[];
			}
			do update_data();
		}
		write "MARL ready: " + length(rl_possible_agents) + " agents, obs_dim=" + rl_obs_dim + ", act_dim=" + rl_act_dim;
	}

	// Apply this year's actions (stored in PetzAgent[0].actions) to the farmers.
	action apply_rl_actions() {
		if (not empty(PetzAgent[0].actions)) {
			loop a over: PetzAgent[0].possible_agents {
				list<float> raw <- list(PetzAgent[0].actions[a]) collect float(each);
				rl_last_action[a] <- raw;
				do apply_rl_action(farmer_by_name[a], raw);
			}
		}
	}

	// Snapshot the year-end transition into PetzAgent and clear the year flag.
	action publish_rl() {
		rl_year_count <- rl_year_count + 1;
		bool done <- rl_year_count >= rl_max_years;
		float gpoll <- empty(Farmer) ? 0.0 : (Farmer mean_of (rl_farm_pollution(each)));
		ask PetzAgent[0] {
			loop a over: possible_agents {
				list<float> la <- world.rl_last_action[a];
				observations[a] <- world.rl_obs(world.farmer_by_name[a]) + la + [
					float(world.rl_year_count) / float(world.rl_max_years)
				];
				// Learning reward depends on the objective mode (profit / pollution / balanced).
				rewards[a] <- (world.rl_reward_mode = 0) ? world.last_year_global_profit :
					((world.rl_reward_mode = 1) ? world.farmer_by_name[a].last_yearly_profit :
					((world.rl_reward_mode = 2) ? (- world.rl_farm_pollution(world.farmer_by_name[a])) :
					(world.farmer_by_name[a].last_yearly_profit - world.rl_balance_weight * world.rl_farm_pollution(world.farmer_by_name[a]))));
				// Expose the TRUE global objectives (profit AND pollution) so evaluation is
				// independent of which reward the policy trained on.
				infos[a] <- ["global_profit"::world.last_year_global_profit, "global_pollution"::gpoll];
				terminations[a] <- false;
				truncations[a] <- done;
			}
			do update_data();
		}
		year_done <- false;
	}

	// ============ Sub-step (seasonal reward) variants — decisions stay annual ============

	// Called by Python when it detects year_done: bank the completed year's profit into the
	// cumulative trackers, advance the year counter and clear the flag. Must run BEFORE
	// rl_publish_substep so the substep delta includes the completed year's tail.
	action rl_finalize_year() {
		rl_completed_profit <- rl_completed_profit + last_year_global_profit;
		loop a over: rl_possible_agents {
			rl_completed_profit_f[a] <- rl_completed_profit_f[a] + farmer_by_name[a].last_yearly_profit;
		}
		rl_year_count <- rl_year_count + 1;
		year_done <- false;
		// New year -> nobody has committed a decision yet.
		rl_decided_count <- 0;
	}

	// Publish one SUB-STEP transition: reward = profit accrued since the previous publish
	// (completed years + the in-progress year), per farmer or global per the mode flag.
	action rl_publish_substep() {
		float cum <- rl_completed_profit + (Farmer sum_of (each.yearly_profit));
		float delta <- cum - rl_prev_cum_profit;
		rl_prev_cum_profit <- cum;
		bool done <- rl_year_count >= rl_max_years;
		float gpoll <- empty(Farmer) ? 0.0 : (Farmer mean_of (rl_farm_pollution(each)));
		ask PetzAgent[0] {
			loop a over: possible_agents {
				list<float> la <- world.rl_last_action[a];
				observations[a] <- world.rl_obs(world.farmer_by_name[a]) + la + [
					float(world.rl_year_count) / float(world.rl_max_years)
				];
				float cum_f <- world.rl_completed_profit_f[a] + world.farmer_by_name[a].yearly_profit;
				float delta_f <- cum_f - world.rl_prev_cum_f[a];
				world.rl_prev_cum_f[a] <- cum_f;
				float poll <- world.rl_farm_pollution(world.farmer_by_name[a]);
				rewards[a] <- (world.rl_reward_mode = 0) ? delta :
					((world.rl_reward_mode = 1) ? delta_f :
					((world.rl_reward_mode = 2) ? (- poll) :
					(delta_f - world.rl_balance_weight * poll)));
				// True global objectives for this window (profit + pollution).
				infos[a] <- ["global_profit"::delta, "global_pollution"::gpoll];
				terminations[a] <- false;
				truncations[a] <- done;
			}
			do update_data();
		}
	}

}

//------------ PetzAgent bridge species (read by the gama-pettingzoo library) ------------
species PetzAgent {
	list<string> agents;
	list<string> possible_agents;
	map<string, unknown> observation_spaces;
	map<string, unknown> action_spaces;

	map<string, unknown> observations;
	map<string, float> rewards;
	map<string, bool> terminations;
	map<string, bool> truncations;
	map<string, map<string, unknown>> infos;

	map<string, unknown> actions;

	map<string, map<string, unknown>> data;

	action update_data() {
		data <- ["Observations"::observations, "Rewards"::rewards, "Terminations"::terminations, "Truncations"::truncations, "Infos"::infos];
	}

	// Store this year's actions and apply them to the farmers. Called as an ACTION-CALL
	// expression from Python (this gama-server build rejects bare assignment statements).
	int set_rl_actions(string js) {
		actions <- from_json(js);
		ask world { do apply_rl_actions(); }
		return length(actions);
	}

	// Snapshot the year-end transition (obs / reward / truncation) and clear year_done.
	action finalize_rl() {
		ask world { do publish_rl(); }
	}

	// Sub-step mode wrappers (called as action-call expressions from Python).
	action finalize_rl_year() {
		ask world { do rl_finalize_year(); }
	}

	action publish_rl_substep() {
		ask world { do rl_publish_substep(); }
	}

	// ---- Sequential decision round (random turn order, driven from Python) ----

	// Fresh observation for ONE farmer at its decision turn. Crucially, the premium-share
	// and decided-fraction signals already reflect the commitments of the farmers that
	// decided EARLIER this year -> a deterministic shared policy can diversify.
	list<float> observe_one(string a) {
		list<float> la <- world.rl_last_action[a];
		return world.rl_obs(world.farmer_by_name[a]) + la + [
			float(world.rl_year_count) / float(world.rl_max_years)
		];
	}

	// Inject and APPLY one farmer's yearly action immediately (so the next farmer in the
	// round observes its effect), and advance the decided counter.
	int set_rl_action_one(string a, string js) {
		list<float> raw <- list(from_json(js)) collect float(each);
		ask world {
			rl_last_action[a] <- raw;
			do apply_rl_action(farmer_by_name[a], raw);
			rl_decided_count <- rl_decided_count + 1;
		}
		return world.rl_decided_count;
	}

	// Select the reward objective (0=global profit, 1=per-farm profit, 2=min pollution,
	// 3=balanced). Called as an action-call expression from Python after each reset.
	int set_reward_mode(int m) {
		ask world { rl_reward_mode <- m; }
		return m;
	}

	// Set the balance weight (lambda) used by the balanced reward (mode 3).
	float set_balance_weight(float w) {
		ask world { rl_balance_weight <- w; }
		return w;
	}
}
//---------------------------------------------------------------------------------------

// MARL entry point loaded by StarfarmParallelEnv over gama-server. The Starfarm simulation
// IS the main experiment here (not a co-model), so client.step advances the clock normally.
experiment marl type: gui {
	parameter "Simple spatial data" var: simple_spatial_data init: true;
	parameter "Custom practices" var: custom_practices init: true;
	parameter "Market retroaction" var: add_market_retroaction init: true;
	parameter "RL controlled" var: rl_controlled init: true;
}

// GUI baseline experiment (internal diffusion model, not RL-controlled) for inspection.
experiment ReinforcementLearning title: "Reinforcement Learning (baseline GUI)" type: gui parent: generic_exp {

	action _init_() {
		
		day_start_of_year <- 300;
		starting_date <- date([2025,1,1]) add_days (day_start_of_year -1);
		use_weather_generator <- true;	
		use_dynamic_market <- true;
		create AbstractStarFarm_model (province:DONG_THAP,simple_spatial_data:true, custom_practices: true, add_market_retroaction: true);
	}

	output {
		layout horizontal([vertical([3::5000,1::5000])::5000,vertical([2::5000,0::5000])::5000]) tabs:true editors: false;
		display map axes: false toolbar: false parent: base_map{}
		display farmer_indicators parent:base_farmer_indicators {}
		display environment_indicators parent:base_environment_indicators {}
		display input_indicators parent:base_input_indicators {}
	}
}
