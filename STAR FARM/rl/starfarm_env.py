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

    # Reward mode: False = shared global reward (project objective), True = per-farmer
    # profit. Stored on the env and (re)applied to GAMA after every reset, because the
    # reload that reset() performs resets the GAML flag back to its default.
    _per_agent_reward = False

    def set_reward_mode(self, per_agent: bool):
        self._per_agent_reward = bool(per_agent)
        self._apply_reward_mode()

    def _apply_reward_mode(self):
        try:
            self.gama_client._execute_expression(
                self.experiment_id,
                f"PetzAgent[0].set_reward_mode({1 if self._per_agent_reward else 0})",
            )
        except Exception as e:
            print(f"Could not set reward mode: {e}")

    def reset(self, *args, **kwargs):
        out = super().reset(*args, **kwargs)
        # Re-apply the reward mode after the reload that reset() triggers.
        self._apply_reward_mode()
        # Year index within the episode (resets each episode); _year_lengths remembers the
        # measured length of each year-slot ACROSS episodes (deterministic env -> it repeats).
        self._episode_year = 0
        if not hasattr(self, "_year_lengths"):
            self._year_lengths = {}
        return out

    def step(self, actions):
        # Encode actions (MultiDiscrete falls back to Gymnasium's to_jsonable -> list).
        gama_actions = {
            agent: self._fast_act_encode(agent, action)
            for agent, action in actions.items()
        }
        actions_json = json.dumps(gama_actions, separators=(",", ":"))

        # Macro-step: apply actions, advance day-by-day until the crop year ends,
        # then snapshot the transition. We drive this ourselves (instead of the
        # library's single-step execute_step) and inject via an ACTION-CALL expression
        # because this GAMA-server build rejects the assignment form
        # `PetzAgent[0].actions <- from_json(...)` (UnableToExecuteRequest). The
        # library itself is left untouched; this lives only in the subclass.
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
