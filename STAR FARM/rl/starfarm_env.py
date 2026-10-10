"""StarfarmParallelEnv: a thin wrapper over gama-pettingzoo's GamaParallelEnv.

Macro-step cadence. The embedded `marl` experiment runs the Starfarm simulation
as the *main* gama-server experiment, so one `client.step` == one simulated DAY
(step <- 1 #day) and the clock (current_date) advances normally — which is what
drives crop phenology, sowing and harvest. One RL year is therefore many server
days, so `env.step()` does the macro-step itself:

    1. PetzAgent[0].set_rl_actions(json)  -> store + apply this year's actions
    2. client.step day-by-day until the world's `year_done` flag is raised by
       the end_of_year reflex (a full crop year has elapsed)
    3. PetzAgent[0].finalize_rl()         -> snapshot obs/reward, clear year_done
    4. read PetzAgent[0].data

This replaces the earlier co-model controler, whose sub-experiment clock never
advanced (current_date stayed frozen -> nothing was ever harvested -> reward 0).
"""

import asyncio
import json
import traceback

import nest_asyncio
import numpy as np
from gama_client.message_types import MessageTypes
from gama_gymnasium import GamaEnvironmentError
from gama_gymnasium.exceptions import GamaCommandError
from gama_pettingzoo.gama_parallel_env import GamaParallelEnv


class StarfarmParallelEnv(GamaParallelEnv):

    metadata = {"name": "StarfarmParallelEnv-v0"}

    # Safety cap on simulated days advanced per RL year (one crop year is ~365 days;
    # a 3-season year stays well under this). Prevents an infinite loop if year_done
    # somehow never fires.
    MAX_DAYS_PER_YEAR = 2000

    # Macro-step batching. A crop year is ~363-383 simulated days. Rather than stepping one
    # day at a time and polling year_done after each (~2 GAMA round-trips/day ≈ 730/year), we
    # jump MIN_DAYS_PER_YEAR days in a SINGLE multi-cycle step (gama_client.step supports
    # nb_step — no library change), then finish day-by-day until year_done. MIN_DAYS_PER_YEAR
    # MUST stay safely BELOW the shortest crop year so the big jump never overshoots the year
    # boundary (exact landing, zero overshoot). 340 is a safe margin under the observed ~363.
    MIN_DAYS_PER_YEAR = 340

    # Safety tail kept un-jumped: the coarse multi-cycle jump goes to (known year length -
    # this margin), then we finish day-by-day so we land exactly on year_done. Small because
    # the env reset is deterministic (year lengths repeat across episodes), so the remembered
    # length is essentially exact; the margin only guards against any residual wobble.
    YEAR_END_MARGIN = 3

    # Number of simulated days advanced during the most recent RL year, and the size of the
    # single coarse jump used for it (for logging the jump-vs-poll split).
    last_days_stepped = 0
    last_coarse_jump = 0

    # Sub-step (seasonal reward) mode: when > 0, one env.step advances at most this many
    # days (or up to year_done) and returns the PROFIT DELTA of that window as reward.
    # Decisions stay annual: actions are only injected when `needs_new_action` is True
    # (episode start and right after each completed year); other steps repeat in-force
    # practices. 0 = legacy annual mode (one step = one full year).
    SUBSTEP_DAYS = 0
    # Days actually advanced by the most recent sub-step (for variable-gamma GAE).
    last_substep_days = 0

    @property
    def needs_new_action(self):
        """True when the next step starts a new decision (new year). In annual mode every
        step is a decision."""
        if self.SUBSTEP_DAYS <= 0:
            return True
        return getattr(self, "_needs_injection", True)

    def __init__(self, *args, **kwargs):
        # gama_client builds its GamaSyncClient with `asyncio.get_running_loop()`
        # in __init__, which raises "no running event loop" when (as here) the env
        # is constructed from plain synchronous code. nest_asyncio (already applied
        # by gama_client.sync_client) lets us nest run_until_complete, so we just
        # need a loop that is *running* while the base __init__ creates the client.
        nest_asyncio.apply()
        try:
            asyncio.get_running_loop()
            super().__init__(*args, **kwargs)
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

            async def _build():
                super(StarfarmParallelEnv, self).__init__(*args, **kwargs)

            loop.run_until_complete(_build())

    # Reward objective: 0=global profit, 1=per-farm profit, 2=minimise pollution,
    # 3=balanced (profit - balance_weight*pollution). Stored on the env and re-applied to
    # GAMA after every reset (the reload that reset() performs resets the GAML defaults).
    _reward_mode = 0
    _balance_weight = 1.0
    _REWARD_MODES = {"global": 0, "per_agent": 1, "pollution": 2, "balanced": 3}

    def set_reward_mode(self, mode, balance_weight=None):
        """mode: int 0-3, a bool (True->per_agent / False->global), or a string
        ('global' / 'per_agent' / 'pollution' / 'balanced'). balance_weight = lambda for
        the balanced objective."""
        if isinstance(mode, bool):
            self._reward_mode = 1 if mode else 0
        elif isinstance(mode, int):
            self._reward_mode = int(mode)
        else:
            self._reward_mode = self._REWARD_MODES.get(str(mode).lower(), 0)
        if balance_weight is not None:
            self._balance_weight = float(balance_weight)
        self._apply_reward_mode()

    def _apply_reward_mode(self):
        try:
            self.gama_client._execute_expression(
                self.experiment_id, f"PetzAgent[0].set_reward_mode({self._reward_mode})")
            self.gama_client._execute_expression(
                self.experiment_id, f"PetzAgent[0].set_balance_weight({self._balance_weight})")
        except Exception as e:
            print(f"Could not set reward mode: {e}")

    # ---- Sequential decision round (random turn order, orchestrated by the trainer) ----

    def observe_one(self, agent_name):
        """Fresh observation for ONE farmer at its decision turn. The premium-share and
        decided-fraction signals already include the commitments injected earlier in the
        round, which is what lets a deterministic shared policy diversify."""
        state = self.gama_client._execute_expression(
            self.experiment_id, f'PetzAgent[0].observe_one("{agent_name}")')
        return np.asarray(state, dtype=np.float32)

    def inject_one(self, agent_name, action):
        """Inject and apply ONE farmer's yearly action immediately."""
        js = json.dumps([float(v) for v in action], separators=(",", ":"))
        self.gama_client._execute_expression(
            self.experiment_id, f"PetzAgent[0].set_rl_action_one(\"{agent_name}\", '{js}')")

    def end_decision_round(self):
        """All farmers have committed this year's actions: the upcoming step() must not
        run the batch injection path."""
        self._needs_injection = False

    def reset(self, *args, **kwargs):
        out = super().reset(*args, **kwargs)
        # Re-apply the reward mode after the reload that reset() triggers.
        self._apply_reward_mode()
        # Year index within the episode (resets each episode); _year_lengths remembers the
        # measured length of each year-slot ACROSS episodes (deterministic env -> it repeats).
        self._episode_year = 0
        if not hasattr(self, "_year_lengths"):
            self._year_lengths = {}
        # Sub-step mode bookkeeping.
        self._needs_injection = True
        self._days_into_year = 0
        return out

    def step(self, actions):
        # Encode actions (MultiDiscrete falls back to Gymnasium's to_jsonable -> list).
        gama_actions = {
            agent: self._fast_act_encode(agent, action)
            for agent, action in actions.items()
        }
        actions_json = json.dumps(gama_actions, separators=(",", ":"))

        # Macro-step: apply actions, advance the simulation, snapshot the transition.
        # We drive this ourselves (instead of the library's single-step execute_step)
        # and inject via an ACTION-CALL expression because this GAMA-server build
        # rejects the assignment form `PetzAgent[0].actions <- from_json(...)`. The
        # library itself is left untouched; this lives only in the subclass.
        if self.SUBSTEP_DAYS > 0:
            step_data = self._macro_substep(actions_json)
        else:
            step_data = self._macro_step_one_year(actions_json)

        observations = {}
        try:
            for agent, state in step_data["Observations"].items():
                observations[agent] = self._fast_obs_convert(agent, state)
        except Exception as e:
            print(f"Step conversion error: {e}")
            traceback.print_exc()
            raise GamaEnvironmentError(f"Failed to convert step observation: {e}")

        rewards = {a: float(r) for a, r in step_data["Rewards"].items()}
        terminated = {a: bool(t) for a, t in step_data["Terminations"].items()}
        truncated = {a: bool(t) for a, t in step_data["Truncations"].items()}
        infos = step_data["Infos"]

        # End of episode: the controler empties its agent list; mirror that here so
        # the training loop's `while env.agents:` exits.
        if (truncated and all(truncated.values())) or (terminated and any(terminated.values())):
            self.agents = []

        return observations, rewards, terminated, truncated, infos

    def _macro_step_one_year(self, actions_json):
        """One RL step == one simulated crop year. Apply the year's actions, advance
        the simulation day-by-day until the world's `year_done` flag is raised by the
        end_of_year reflex, then snapshot the transition and read it back.

        Writes go through ACTION-CALL expressions (set_rl_actions / finalize_rl): this
        build's expression endpoint rejects bare assignment statements. The library is
        left untouched; this lives only in the subclass."""
        client = self.gama_client            # GamaClientWrapperPtZ
        exp_id = self.experiment_id

        # 1. Store + apply this year's actions for every farmer (side-effecting call).
        #    actions_json uses double quotes; wrap it in single quotes for the GAML
        #    string literal. Farmer ids like "Farmer(0)" are plain JSON string keys.
        client._execute_expression(exp_id, f"PetzAgent[0].set_rl_actions('{actions_json}')")

        # 2. Advance one crop year, minimising GAMA<->Python round-trips:
        #    (a) ONE coarse multi-cycle jump sized from how many days THIS year-slot took
        #        last episode (the env reset is deterministic, so it repeats); the first time
        #        we hit a slot we fall back to the safe lower bound MIN_DAYS_PER_YEAR.
        #    (b) then one day at a time until year_done — landing exactly on the boundary
        #        without overshooting into the next year.
        def _do_steps(n):
            if n <= 0:
                return
            response = client.client.step(exp_id, nb_step=n, sync=True)
            if response["type"] != MessageTypes.CommandExecutedSuccessfully.value:
                raise GamaCommandError(f"Failed to execute step: {response}")

        k = getattr(self, "_episode_year", 0)
        if not hasattr(self, "_year_lengths"):
            self._year_lengths = {}

        if k in self._year_lengths:
            coarse = max(1, self._year_lengths[k] - self.YEAR_END_MARGIN)
        else:
            coarse = self.MIN_DAYS_PER_YEAR
        coarse = min(coarse, self.MAX_DAYS_PER_YEAR)
        self.last_coarse_jump = coarse

        days = 0
        _do_steps(coarse)              # single round-trip for the bulk of the year
        days += coarse

        # `year_done` is set true by end_of_year and stays true until finalize_rl clears it.
        polled = 0
        while days < self.MAX_DAYS_PER_YEAR:
            if bool(client._execute_expression(exp_id, "year_done")):
                break
            _do_steps(1)
            days += 1
            polled += 1
        else:
            raise GamaEnvironmentError(
                f"year_done never raised within {self.MAX_DAYS_PER_YEAR} simulated days"
            )

        # Update this year-slot's jump estimate. Year length is now ACTION-DEPENDENT (cultivar
        # and season count change maturity timing), so guard against overshoot: if the coarse
        # jump already reached/passed the boundary (polled == 0) we can't know the true length,
        # so pull the estimate back; otherwise record the shortest length actually observed.
        # NB: the reward is unaffected by a small overshoot — it reads the year-end snapshot
        # (last_year_global_profit) set at end_of_year, which a few extra days don't change.
        if polled == 0:
            self._year_lengths[k] = max(1, coarse - 2 * self.YEAR_END_MARGIN)
        else:
            self._year_lengths[k] = min(self._year_lengths.get(k, days), days)
        self.last_days_stepped = days
        self._episode_year = k + 1

        # 3. Snapshot obs/reward/truncation into PetzAgent and clear year_done.
        client._execute_expression(exp_id, "PetzAgent[0].finalize_rl()")

        # 4. Read the published transition bundle.
        return client._execute_expression(exp_id, "PetzAgent[0].data")

    def _macro_substep(self, actions_json):
        """One env.step == one SUB-STEP of at most SUBSTEP_DAYS simulated days (less if the
        crop year ends inside the window). Reward = profit delta over the window. Actions
        are injected only at year starts (decisions stay annual); the coarse multi-cycle
        jump + fine daily polling near the expected year end is kept, so the round-trip
        batching survives the sub-step granularity."""
        client = self.gama_client
        exp_id = self.experiment_id

        # Inject this year's actions only at a decision point (episode start / new year).
        if self._needs_injection:
            client._execute_expression(exp_id, f"PetzAgent[0].set_rl_actions('{actions_json}')")
            self._needs_injection = False

        def _do_steps(n):
            if n <= 0:
                return
            response = client.client.step(exp_id, nb_step=n, sync=True)
            if response["type"] != MessageTypes.CommandExecutedSuccessfully.value:
                raise GamaCommandError(f"Failed to execute step: {response}")

        k = getattr(self, "_episode_year", 0)
        expected = self._year_lengths.get(k, self.MIN_DAYS_PER_YEAR)
        fine_zone_start = max(0, expected - self.YEAR_END_MARGIN)

        consumed = 0
        year_done = False
        while consumed < self.SUBSTEP_DAYS:
            if self._days_into_year < fine_zone_start:
                # Coarse: one batched jump to the end of this sub-step OR the fine zone.
                jump = min(self.SUBSTEP_DAYS - consumed, fine_zone_start - self._days_into_year)
                _do_steps(jump)
                consumed += jump
                self._days_into_year += jump
                # One check after the jump (the year can end early if the memo over-estimated).
                if bool(client._execute_expression(exp_id, "year_done")):
                    year_done = True
                    break
            else:
                # Fine zone: daily stepping with year_done polling.
                _do_steps(1)
                consumed += 1
                self._days_into_year += 1
                if bool(client._execute_expression(exp_id, "year_done")):
                    year_done = True
                    break
            if self._days_into_year >= self.MAX_DAYS_PER_YEAR:
                raise GamaEnvironmentError(
                    f"year_done never raised within {self.MAX_DAYS_PER_YEAR} simulated days")

        if year_done:
            # Bank the completed year (profit trackers + year counter + clears year_done),
            # update the year-length memo, and require a fresh decision next step.
            client._execute_expression(exp_id, "PetzAgent[0].finalize_rl_year()")
            self._year_lengths[k] = min(self._year_lengths.get(k, self._days_into_year),
                                        self._days_into_year)
            self.last_days_stepped = self._days_into_year
            self._episode_year = k + 1
            self._days_into_year = 0
            self._needs_injection = True

        self.last_substep_days = consumed

        # Publish the sub-step transition (profit delta, obs, truncation) and read it.
        client._execute_expression(exp_id, "PetzAgent[0].publish_rl_substep()")
        return client._execute_expression(exp_id, "PetzAgent[0].data")
