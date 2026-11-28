class_name DestLeeSkillEffects
extends RefCounted
const G=preload("res://scripts/battle/grid_rules.gd")
const M=preload("res://scripts/battle/combat_math.gd")
const E=preload("res://scripts/battle/skill_executor.gd")
const IGNITION:StringName=&"dest_lee_ignition"
const EMBER_ACTION="dest_lee_death_embers"
const DOT_ACTION="dest_lee_ignition_dot"
const ONE_DOT=0.25
const TWO_DOT=0.40
const ORTHO=0.80
const DIAGONAL=0.40
const SPLASH=0.50
static func _ray_clear(a:Vector2i,b:Vector2i,blockers:Dictionary,ignore_end:bool)->bool:
	var x=a.x
	var y=a.y
	var dx=absi(b.x-x)
	var dy=absi(b.y-y)
	var sx=1 if x<b.x else -1
	var sy=1 if y<b.y else -1
	var err=dx-dy
	while x!=b.x or y!=b.y:
		var twice=err*2
		if twice>-dy:
			err-=dy
			x+=sx
		if twice<dx:
			err+=dx
			y+=sy
		var cell:=Vector2i(x,y)
		if ignore_end and cell==b:
			break
		if blockers.has(cell):
			return false
	return true
static func can_aim(battle,skill,target)->bool:
	var caster=battle.get_active_character()
	if caster==null or target==null or not caster.is_alive() or not target.is_alive():
		return false
	var d=G.manhattan_distance(caster.cell,target.cell)
	return d>=skill.min_range and d<=skill.max_range and d<=2 and (d<=1 or _ray_clear(caster.cell,target.cell,battle.get_sight_blockers(caster.actor_id),true))
static func can_aim_cell(battle,skill,aim:Vector2i)->bool:
	var caster=battle.get_active_character()
	if caster==null or not caster.is_alive() or not G.is_inside_bounds(aim,battle.grid_size):
		return false
	var d=G.manhattan_distance(caster.cell,aim)
	return d>=skill.min_range and d<=skill.max_range and _ray_clear(caster.cell,aim,battle.get_sight_blockers(caster.actor_id),true)
static func area_cells(battle,skill,aim:Vector2i)->Dictionary:
	if not can_aim_cell(battle,skill,aim):
		return {}
	var cells:Dictionary={}
	for y in range(-skill.shape_radius,skill.shape_radius+1):
		for x in range(-skill.shape_radius,skill.shape_radius+1):
			if absi(x)+absi(y)>skill.shape_radius:
				continue
			var cell:=aim+Vector2i(x,y)
			if not G.is_inside_bounds(cell,battle.grid_size):
				continue
			if cell!=aim and battle.blocked_cells.has(cell):
				continue
			if not _ray_clear(aim,cell,battle.blocked_cells,true):
				continue
			cells[cell]=true
	return cells
static func _lee(battle):
	return battle.get_actor("dest_lee")
static func _can_cast(battle,caster,skill)->bool:
	return caster!=null and caster.is_alive() and battle.phase==battle.BattlePhase.PLAYER and battle.ap.can_spend(skill.ap_cost)
static func _ignite(battle,target,amount:int)->void:
	if target==null or not target.is_alive():
		return
	var lee=_lee(battle)
	if lee==null or not battle.statuses.apply_status(IGNITION,lee.actor_id,target.actor_id,amount,2,-1,&"",&"add"):
		return
	var status=battle.statuses.get_status(target.actor_id,IGNITION)
	if status==null:
		return
	status.enemy_turns_remaining=3 if battle.phase==battle.BattlePhase.ENEMY else 2
	battle._emit_event("status_applied",lee.actor_id,target.actor_id,"status=dest_lee_ignition stacks=%d turns=2"%status.stacks)
static func begin_batch(battle)->void:
	if battle.dest_lee_batch_depth==0:
		battle.dest_lee_death_queue.clear()
	battle.dest_lee_batch_depth+=1
static func end_batch(battle)->void:
	battle.dest_lee_batch_depth=maxi(0,battle.dest_lee_batch_depth-1)
	if battle.dest_lee_batch_depth==0:
		_resolve_queue(battle)
static func on_target_defeated(battle,target,source_id:String,action_id:String)->void:
	if target==null or target.team!="enemy" or action_id==EMBER_ACTION or not battle.has_passive("dest_lee",&"dest_lee_death_embers"):
		return
	var status=battle.statuses.get_status(target.actor_id,IGNITION)
	if status==null or status.stacks<=0:
		return
	var source=battle.actors.get(source_id)
	var direct=source!=null and source.team=="player"
	var dot=action_id==DOT_ACTION and source_id=="dest_lee"
	if not direct and not dot:
		return
	battle.dest_lee_death_queue.append({"actor_id":String(target.actor_id),"cell":target.cell,"stacks":status.stacks})
	if battle.dest_lee_batch_depth==0:
		_resolve_queue(battle)
static func _resolve_queue(battle)->void:
	if battle.dest_lee_chain_active or battle.dest_lee_death_queue.is_empty():
		return
	battle.dest_lee_chain_active=true
	battle.dest_lee_chain_hit_targets.clear()
	while not battle.dest_lee_death_queue.is_empty():
		battle.dest_lee_death_queue.sort_custom(func(a,b):return String(a.actor_id)<String(b.actor_id))
		_resolve_ember(battle,battle.dest_lee_death_queue.pop_front())
	battle.dest_lee_chain_active=false
	battle.dest_lee_chain_hit_targets.clear()
static func _resolve_ember(battle,death:Dictionary)->void:
	var lee=_lee(battle)
	if lee==null:
		return
	var center:Vector2i=death.cell
	var targets:Array=[]
	for id in battle.actors.keys():
		var actor=battle.actors[id]
		if actor.team!="enemy" or not actor.is_alive():
			continue
		var dx=absi(actor.cell.x-center.x)
		var dy=absi(actor.cell.y-center.y)
		if dx<=1 and dy<=1 and _ray_clear(center,actor.cell,battle.blocked_cells,true):
			targets.append(actor)
	targets.sort_custom(func(a,b):return String(a.actor_id)<String(b.actor_id))
	for target in targets:
		if not battle.dest_lee_chain_hit_targets.has(target.actor_id):
			battle.dest_lee_chain_hit_targets[target.actor_id]=true
			var dx=absi(target.cell.x-center.x)
			var dy=absi(target.cell.y-center.y)
			var mult=ORTHO if dx==0 or dy==0 else DIAGONAL
			battle._apply_damage(target.actor_id,M.calculate_raw_damage(lee.attack,mult),lee.actor_id,EMBER_ACTION,"magical")
		if target.is_alive():
			_ignite(battle,target,1)
	for cell in battle.beacons.keys():
		var dx=absi(cell.x-center.x)
		var dy=absi(cell.y-center.y)
		if dx>1 or dy>1 or (dx==0 and dy==0) or not _ray_clear(center,cell,battle.blocked_cells,true):
			continue
		var mult=ORTHO if dx==0 or dy==0 else DIAGONAL
		battle.damage_beacon_at(cell,M.calculate_raw_damage(lee.attack,mult),lee.actor_id,EMBER_ACTION,true)
	battle._emit_event("dest_lee_death_ember",lee.actor_id,String(death.actor_id),"cell=%s stacks=%d"%[str(center),int(death.stacks)])
static func _damage_objects(battle,cells:Dictionary,caster,mult:float,action:String)->void:
	var raw=M.calculate_raw_damage(caster.attack,mult)
	for cell in cells.keys():
		if battle.beacons.has(cell):
			battle.damage_beacon_at(cell,raw,caster.actor_id,action,true)
static func _run_blackflame_shot(battle,skill,target_id:String)->bool:
	var caster=battle.get_active_character()
	var target=battle.actors.get(target_id)
	if not _can_cast(battle,caster,skill) or target==null or target.team!="enemy" or not can_aim(battle,skill,target):
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false
	begin_batch(battle)
	battle._apply_damage(target.actor_id,M.calculate_raw_damage(caster.attack,skill.damage_multiplier),caster.actor_id,String(skill.skill_id),"magical")
	if target.is_alive():
		_ignite(battle,target,1)
	end_batch(battle)
	E.gain_active_energy(battle,caster.actor_id)
	battle._emit_event("attack_resolved",caster.actor_id,target.actor_id,String(skill.skill_id))
	battle._check_battle_end()
	return true
static func _run_black_rain(battle,skill,aim:Vector2i)->bool:
	var caster=battle.get_active_character()
	if not _can_cast(battle,caster,skill):
		return false
	var cells=area_cells(battle,skill,aim)
	if cells.is_empty() or not battle.ap.spend(skill.ap_cost):
		return false
	var targets:Array=[]
	for id in battle.actors.keys():
		var actor=battle.actors[id]
		if actor.team=="enemy" and actor.is_alive() and cells.has(actor.cell):
			targets.append(actor)
	targets.sort_custom(func(a,b):return String(a.actor_id)<String(b.actor_id))
	begin_batch(battle)
	var raw=M.calculate_raw_damage(caster.attack,skill.damage_multiplier)
	for target in targets:
		battle._apply_damage(target.actor_id,raw,caster.actor_id,String(skill.skill_id),"magical")
	for target in targets:
		if target.is_alive():
			_ignite(battle,target,2)
	_damage_objects(battle,cells,caster,skill.damage_multiplier,String(skill.skill_id))
	end_batch(battle)
	E.gain_active_energy(battle,caster.actor_id)
	battle._emit_event("skill_resolved",caster.actor_id,"","skill=dest_lee_black_rain targets=%d"%targets.size())
	battle._check_battle_end()
	return true
static func _run_city_burn(battle,skill,_target:String="")->bool:
	var caster=battle.get_active_character()
	if not _can_cast(battle,caster,skill):
		return false
	var centers:Array[Dictionary]=[]
	for id in battle.actors.keys():
		var actor=battle.actors[id]
		if actor.team!="enemy" or not actor.is_alive():
			continue
		var status=battle.statuses.get_status(actor.actor_id,IGNITION)
		if status!=null and status.stacks>0:
			centers.append({"actor_id":String(actor.actor_id),"cell":actor.cell})
	centers.sort_custom(func(a,b):return String(a.actor_id)<String(b.actor_id))
	if centers.is_empty() or not battle.ap.spend(skill.ap_cost):
		return false
	var enemies:Array=[]
	for id in battle.actors.keys():
		var actor=battle.actors[id]
		if actor.team=="enemy" and actor.is_alive():
			enemies.append({"actor":actor,"cell":actor.cell})
	enemies.sort_custom(func(a,b):return String(a.actor.actor_id)<String(b.actor.actor_id))
	begin_batch(battle)
	for entry in enemies:
		var enemy=entry.actor
		var direct=false
		var splash=false
		for center in centers:
			var c:Vector2i=center.cell
			var cell:Vector2i=entry.cell
			var dx=absi(cell.x-c.x)
			var dy=absi(cell.y-c.y)
			if dx<=1 and dy<=1 and _ray_clear(c,cell,battle.blocked_cells,true):
				splash=true
				if String(center.actor_id)==String(enemy.actor_id):
					direct=true
		if direct or splash:
			var mult=1.5 if direct else SPLASH
			battle._apply_damage(enemy.actor_id,M.calculate_raw_damage(caster.attack,mult),caster.actor_id,String(skill.skill_id),"magical")
	for center in centers:
		for cell in battle.beacons.keys():
			var dx=absi(cell.x-center.cell.x)
			var dy=absi(cell.y-center.cell.y)
			if dx<=1 and dy<=1 and _ray_clear(center.cell,cell,battle.blocked_cells,true):
				battle.damage_beacon_at(cell,M.calculate_raw_damage(caster.attack,SPLASH),caster.actor_id,String(skill.skill_id),true)
	end_batch(battle)
	for center in centers:
		battle.statuses.remove_status(String(center.actor_id),IGNITION)
	E.gain_active_energy(battle,caster.actor_id)
	battle._emit_event("skill_resolved",caster.actor_id,"","skill=dest_lee_city_burn targets=%d"%centers.size())
	battle._check_battle_end()
	return true
static func _run_daybreak_ends(battle,skill,aim:Vector2i)->bool:
	var caster=battle.get_active_character()
	if not _can_cast(battle,caster,skill):
		return false
	var cells=area_cells(battle,skill,aim)
	if cells.is_empty() or caster.ultimate_energy<caster.ultimate_energy_max:
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false
	if not caster.spend_ultimate_energy(caster.ultimate_energy_max):
		battle.ap.refund(skill.ap_cost)
		return false
	for mult in skill.hit_multipliers:
		var targets:Array=[]
		for id in battle.actors.keys():
			var actor=battle.actors[id]
			if actor.team=="enemy" and actor.is_alive() and cells.has(actor.cell):
				targets.append(actor)
		targets.sort_custom(func(a,b):return String(a.actor_id)<String(b.actor_id))
		begin_batch(battle)
		var raw=M.calculate_raw_damage(caster.attack,mult)
		for target in targets:
			battle._apply_damage(target.actor_id,raw,caster.actor_id,String(skill.skill_id),"magical")
		for target in targets:
			if target.is_alive():
				_ignite(battle,target,1)
		_damage_objects(battle,cells,caster,mult,String(skill.skill_id))
		end_batch(battle)
	battle._emit_event("skill_resolved",caster.actor_id,"","skill=dest_lee_daybreak_ends aim=%s rounds=4"%str(aim))
	battle._check_battle_end()
	return true
static func tick_ignition(battle)->void:
	var ids:Array[String]=[]
	for id in battle.actors.keys():
		if battle.statuses.get_status(String(id),IGNITION)!=null:
			ids.append(String(id))
	ids.sort()
	var lee=_lee(battle)
	if lee==null:
		return
	for id in ids:
		var target=battle.actors.get(id)
		var status=battle.statuses.get_status(id,IGNITION)
		if target==null or not target.is_alive() or status==null or status.enemy_turns_remaining==3:
			continue
		var mult=TWO_DOT if status.stacks>=2 else ONE_DOT
		battle._apply_damage(id,M.calculate_raw_damage(lee.attack,mult),lee.actor_id,DOT_ACTION,"magical")
