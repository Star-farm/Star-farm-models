# Methodology Note: Multi-Agent Reinforcement Learning Training

**Starfarm project, decision-making component (farmers)**
*Document intended for review by RL experts. July 2026*

This note describes the **training methodology only**. The underlying simulator (a GAMA
agronomic model) is treated as a black box: only the learning interface and the algorithmic
choices are exposed here. The goal is to allow a judgement on the **coherence and quality** of
the training loop.

---

## 1. Problem formalisation

The problem is cast as a **partially observable multi-agent Markov game (Dec-POMDP)**:

- **N homogeneous agents** (farmers) acting in parallel.
- **Partial observability**: each agent observes its local state plus aggregate market
  signals, never the full global state.
- **Market coupling across agents**: the price is endogenous (overproducing a premium good
  drives its price down). Rewards are therefore **neither additive nor stationary** from the
  point of view of an isolated agent, which motivates a centralized critic.
- **Finite horizon**: 25 decision steps (years), termination by truncation; `gamma = 0.97`.
- **Configurable reward**: cooperative (global profit) or individual (own profit), plus two
  alternative objectives (minimising an environmental cost; a weighted combination). The mode
  affects only the learning signal, not the evaluation metric.

## 2. Temporal abstraction (semi-MDP)

- **One RL decision equals one simulated year**: farming practices are chosen annually.
  Actions are resampled only at year boundaries.
- **Dense reward per seasonal sub-step (about 122 days)**: a semi-MDP formulation. Decisions
  remain annual, but the critic receives a **dense intra-year** value signal, which reduces the
  variance of the value estimate.
- **GAE with a variable discount factor**: a sub-step covering `d` days discounts by
  `gamma^(d/365)`, so that discounting stays consistent despite the variable granularity.
- *(Simulator engineering, outside RL semantics: steps are grouped into a batched macro-step to
  limit round-trips with the simulator; no effect on learning.)*

## 3. Spaces

### Observation: `Box(18)`, per agent, normalised online

| Block | Dim. | Content |
|---|---|---|
| Local state | 4 | previous annual profit, mean fertiliser, soil health, yield |
| Local environment | 2 | pollution, salinity |
| Static descriptors | 2 | number of plots, area; enable specialisation of a shared actor |
| Market / coordination signals | 3 | premium share, relative premium price, fraction of agents already decided |
| Last action | 6 | memory of the previous decision |
| Time | 1 | normalised year index (remaining horizon) |

The deliberate absence of **any agent identifier** makes the actor invariant to the number of
agents.

### Action: `Box(6)`, continuous in `[0,1]`

A continuous vector decoded into practices (one binary selector per practice via a 0.5
threshold, plus one continuous quantity for irrigation). The policy is a **diagonal Gaussian**;
the `[0,1]` bound is enforced simulator-side by clipping (see section 12, known limitation).

### Reward: 4 modes

`global profit`, `per-agent profit`, `-pollution`, `profit - lambda * pollution`.
The **evaluation metric** (true global profit and pollution) is computed and exposed separately
from the learning signal, which makes the modes directly comparable.

## 4. Sequential intra-year decision protocol

Each year, agents decide **one at a time, in a random order**. Each agent observes the market
state **already updated** by the commitments of the agents that decided before it (dynamic
premium share, decided fraction). Rationale: a shared deterministic policy is symmetric; on a
market with decreasing returns (a minority-game / El Farol dynamic), that symmetry prevents
diversification. The sequential order provides the **symmetry-breaking** mechanism without
resorting to an agent identifier.

## 5. Algorithm: MAPPO (CTDE)

A **centralized training, decentralized execution** framework:

- **Decentralized shared-weight actor**: acts on the local observation only; execution is
  independent of N.
- **Centralized critic**: receives the **global state** (concatenation of all agents'
  normalised observations); used at training time only.
- **Clipped, on-policy PPO** optimisation (clip 0.2).

## 6. Architectures

| Network | Body | Head | Notes |
|---|---|---|---|
| Actor (shared) | MLP 2 x 128, tanh | linear mean + learned `log_std` | global `log_std` (init -1.2), state-independent; diagonal Normal |
| Critic (centralized) | MLP 2 x 256, tanh | scalar | input = `obs_dim x N` |

A single **Adam** optimiser over the actor and critic parameters.

## 7. Advantage estimation and value targets

- **GAE(`lambda = 0.95`)** with per-sub-step variable discounting.
- **Per-decision advantage**: GAE evaluated at the **first sub-step** of the year, intended to
  summarise the discounted future from the decision point.
- **Two credit regimes**: (i) team reward, one shared advantage per time step; (ii) per-agent
  reward, the centralized critic predicts the **mean per-agent return**, and the individual
  advantage is the own return relative to that shared baseline.
- **Dual-batch update**: the **actor** learns only on **decision** transitions (annual); the
  **critic** learns on **all sub-steps** (dense target), at identical simulator cost.
- **Advantage normalisation** per mini-batch.

## 8. Stabilisation and regularisation

- **Observation normalisation**: running mean and variance (Welford).
- **Adaptive value-target normalisation**: a running scalar standard deviation, replacing a
  fixed reward-scale factor. The critic learns on normalised targets; the value is de-normalised
  before the GAE computation (advantages stay in raw scale).
- **Entropy decay**: coefficient annealed linearly (0.01 to 0.001).
- **KL early stopping**: actor epochs stop when `approx_KL > 1.5 * target_kl`; the critic
  completes its full cycle.
- **Gradient clipping** (norm 0.5), separate for actor and critic.
- **Linear learning-rate annealing** over the training run.

## 9. Hyperparameters

| Parameter | Value | Parameter | Value |
|---|---|---|---|
| Algorithm | MAPPO (CTDE) | `gamma` | 0.97 |
| `gae_lambda` | 0.95 | PPO clip | 0.2 |
| epochs / update (`k_epochs`) | 4 | mini-batch | 64 |
| `lr` | 3e-4 (annealed to 0) | `target_kl` | 0.03 |
| entropy coef | 0.01 to 0.001 | `value_coef` | 0.5 |
| actor width | 128 | critic width | 256 |
| `obs_dim` | 18 | `act_dim` | 6 |
| N (training) | 10 | sub-step | 122 days |
| horizon | 25 years | sequential decisions | yes |
| obs normalisation | yes | seed | 0 |
| episodes | 400 to 600 per run | grad clip | 0.5 |

## 10. Evaluation, checkpointing, generalisation

- **Periodic greedy evaluation** (every 25 episodes): a deterministic policy (the Gaussian
  mean) measuring the true objective. Used as the best-checkpoint selection criterion.
- **True objective always exposed** (profit and pollution) regardless of the training mode,
  giving a fair cross-mode comparison.
- **Determinism**: the environment reset is deterministic (reproducible year lengths); the
  inter-episode variance of the global profit is low (CV about 0.4 percent), most of the
  randomness coming from the sequential decision order.
- **Scale generalisation**: because the actor carries no agent identifier, a policy trained on
  10 agents was transferred as is to **748 agents without retraining** (decentralized
  execution), which served as a robustness test.
- **Complete checkpoints**: actor and critic weights, optimiser state, observation and value
  normalisation statistics, allowing exact resumption.

## 11. Structural decisions and rationale

| Decision | Rationale |
|---|---|
| Shared actor with no agent identifier | invariance to the number of agents and scale transfer; symmetry-breaking is provided by the sequential protocol, not by an identifier |
| CTDE / centralized critic | market coupling makes the environment non-stationary for an independent critic; the global critic improves credit assignment |
| Continuous `Box` actions (vs MultiDiscrete) | smoother space, a single Gaussian head, tunable irrigation quantity |
| Semi-MDP with dense reward | reduces critic variance without changing the annual decision granularity |
| Adaptive value normalisation | return magnitudes vary strongly across reward modes; a fixed scale factor would be miscalibrated |

## 12. Known limitations and points submitted for review

1. **Unbounded Gaussian policy**, bounded by simulator-side clipping: a gradient bias at the
   bounds. A `tanh` squashing with log-probability correction would be more rigorous.
2. **Best-checkpoint selection by greedy profit**, including for non-profit objectives: the
   "best" checkpoint may be misaligned with the objective actually trained. Worked around by
   evaluating the final checkpoints for those objectives.
3. **Single greedy episode per policy** at evaluation: profit variance is low and quantified
   (CV about 0.4 percent), but the variance of secondary objectives is not quantified.
4. **State-independent `log_std`**: homogeneous, non-adaptive exploration.
5. **Degenerate local optimum** observed for the single-objective "pollution only" reward
   (exploration collapse once the profit signal is removed), suggesting that exploration
   depends on the shaping provided by profit.
6. **On-policy (PPO)**: limited sample efficiency, since each episode requires a full, costly
   rollout of the simulator.
7. **Reproducibility**: a single seed, no multi-seed confidence intervals; the configuration
   files are not versioned.
8. **Intra-year credit assignment**: the decision advantage is taken at the first sub-step; the
   assumption that this point summarises the discounted future has not been validated by
   ablation.
9. **KL early stopping** occasionally triggered on the very first mini-batch (observation
   normalisation drift between collection and update): cosmetic, self-correcting.

---

*Available on request: training logs (per-episode returns, periodic greedy evaluations),
convergence curves, and the source code of the training loop.*
