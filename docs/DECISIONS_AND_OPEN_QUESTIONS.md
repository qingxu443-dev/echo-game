# ECHO — Decisions and Open Questions

Use these labels consistently:

- **Confirmed** — explicitly approved by the project owner.
- **Planning baseline** — current planning direction, not necessarily final.
- **Open** — requires a decision.
- **To test** — requires prototype evidence.
- **Rejected** — explicitly ruled out.

## Confirmed foundations

- 2D turn-based tactical roguelite.
- Android, landscape-first; single-player and offline.
- Godot 4.x with GDScript.
- Pure top-down square-grid battlefield.
- Prototype movement costs 1 AP and moves up to two orthogonal cells.
- Base player turn budget is 3 AP.
- Actions resolve immediately and may only be canceled before target confirmation.
- Enemy telegraphs are generated at the start of the player turn.
- Telegraph targeting uses a mixed model: each action may lock to an actor, a grid cell, or an area according to its design; the telegraph must communicate the selected mode.
- Actor-locked attacks continue tracking their designated actor; tile-locked attacks resolve at the originally marked cell; area-locked attacks resolve in the originally marked area.
- If an actor-locked action's designated target is defeated before execution, that action is canceled, does not retarget another actor, and does not refund or compensate player AP; the enemy's action slot is considered resolved.
- A successful control/interruption immediately cancels the affected enemy's current telegraph; a failed control leaves that telegraph unchanged. The effect does not alter other enemies' telegraphs.
- Enemy execution order is fixed and visibly communicated: sort by predefined enemy action priority, then by stable battlefield position for ties; show the complete order before the enemy phase and keep it fixed for that phase.
- Prototype 0.1 enemy intent selection uses deterministic priorities: eligible special actions first, ordinary attacks second, movement or waiting last; ties use a fixed deterministic rule, not a fresh random choice. Once telegraphed, the intent is not freely reselected at execution time.
- Earlier enemy actions do not silently rewrite later enemies' telegraphed targets: actor locks continue tracking the same actor, tile locks resolve at the original cell, and area locks resolve in the original area. If a later action becomes genuinely impossible because the battlefield changed, cancel it rather than retargeting or generating a replacement attack.
- Terrain changes do not silently alter existing telegraphs: if the original action remains possible, it resolves at its original target/area; if terrain makes it impossible, cancel it. Terrain changes cannot silently expand its area or change its target.
- If an enemy's telegraphed action cannot legally execute at resolution time, cancel it without selecting a new target or switching skills, do not refund/compensate player AP, and record the cancellation reason in the battle log/debug event.
- An enemy's telegraph is canceled immediately when that enemy dies.
- Prototype companion actions are player-commanded, then automatically executed; the companion has one independent support action per player turn.
- No mid-run saves, checkpoints, or run restoration. Out-of-run progression may persist.
- ECHO and Shiguang must remain completely separate.

## Prototype 0.1 scope baseline

One playable Oathkeeper (Sevrin), one temporary Hunter companion, three ordinary enemy types, one battlefield, four player-facing skill slots plus the Oath Vow passive (verified against the shipped skill bar, 2026-11-25; the earlier "five to six skills" predates the V2 kit), the AP and telegraph systems, victory/defeat resolution, and Android touch interaction.

Confirmed enemy battlefield roles: melee vanguard (close-range pressure), ranged marksman (long-range threat), and area controller (area denial). The melee vanguard's approved behavior direction is hybrid: normally pursues and applies steady melee pressure, then uses a charged strike when conditions are met. Exact trigger conditions and all action details remain open. Other identities, art, stats, exact actions, targeting assignments, and numerical values remain open.

## Maintainer-selected planning baselines (delegated autonomy)

The project owner delegated detailed Prototype 0.1 design and implementation decisions to the maintainer while unavailable. The following are selected implementation baselines, not claims of explicit owner review; numerical values remain subject to playtesting.

- Melee Vanguard (numbers verified against `data/enemies/vanguard.tres` and the intent planner, 2026-11-25): 3200 health, 1400 attack, 700 defense, 350 magic resistance. Pursuit up to 2 orthogonal cells; adjacent actor-locked basic melee at 0.8x attack; straight-line distance-2 tile-locked charged strike at 1.5x attack. Selection priority is charged strike (0), basic attack (1), pursuit (2), wait (3). Target and action are captured at telegraph generation; no execution-time retargeting.
- Melee Vanguard target selection: the intent generator locks onto Sevrin only. There is no health-ratio or distance-based target choice, because the prototype has exactly one player-side actor. This supersedes the earlier "lowest health ratio, then stable actor ID" note, which described a roster the prototype does not have.
- Pursuit pathfinding uses a deterministic neighbor order (up, right, down, left); no diagonal movement or traversal through blocked/occupied cells.
- These values are first-pass encounter tuning, not final balance. The earlier numbers in this section (6 HP, 1 and 2 damage) predate the integer-stat model and are superseded by the values above.

## Open questions — do not silently decide in code

- Which targeting mode (actor-locked, tile-locked, or area-locked) should each individual Prototype 0.1 enemy action use?
- Do tile-locked or area-locked actions have additional range/line-of-sight invalidation conditions after telegraph generation?
- How should overlapping telegraphs be layered and inspected on a phone screen?
- What is the final event-resolution order for damage, death, status effects, telegraph cancellation, and triggers?
- What are the final damage, armor, health, and control formulas?

## Proposed by `docs/design/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md` (Draft) — awaiting owner review

The system-laws document is a Draft and proposes two changes to this file. Neither is applied below, because a draft cannot amend a confirmed rule on its own authority.

- **Open — document interface clauses (§1.1).** Proposed split of responsibility: the world overview and prologue may produce atmosphere, art direction and marketing copy only, never world rules or mechanism explanations; the system-laws document may produce laws and mechanism explanations, never copy or scripts; on conflict the system-laws document wins, and the older text is void without being rewritten. Needs a decision before it constrains future writing.
- **Open — reclassify the no-retarget family.** The entries above about "cancel instead of retarget / never reselect at execution time / terrain must not silently alter telegraphs" are currently **Confirmed** as independently approved rules. The proposal is that, once Law 1 (既定回响) is confirmed, these become **corollaries derived from it** rather than separately approved decisions. They stay Confirmed until Law 1 is confirmed; the reclassification is not applied yet.

Two further notes from the same review, recorded here so they are not lost:

- The laws document claims a "skill cooldown" mechanism for Law 2, but only the hunter summon has a cooldown; the four active skills have none. Either the law's wording or the skill design has to change.
- Law 4 (per-level anomaly) assumes the mitigation constant `K` can be overridden per level. `K` is currently a literal inside `CombatMath.calculate_damage`, so no anomaly can be expressed until it becomes an injectable parameter. This is a prerequisite, not a detail.


## To test

- Battlefield dimensions and camera scale.
- Touch target sizes and long-press behavior.
- Telegraph readability with multiple enemies.
- Encounter pacing and skill balance.
- Performance on target Android hardware.
