extends "res://tests/framework/test_case.gd"
const B=preload("res://scripts/battle/battle_controller.gd")
const C=preload("res://scripts/battle/character_catalog.gd")
const R=preload("res://scripts/battle/skill_registry.gd")
const Runtime=preload("res://scripts/battle/character_skill_runtime.gd")
const Lee=preload("res://scripts/battle/dest_lee_skill_effects.gd")
const Math=preload("res://scripts/battle/combat_math.gd")
const IGNITION:StringName=&"dest_lee_ignition"
func _run()->void:
	_sheet()
	_blackflame()
	_black_rain()
	_dot()
	_city_burn()
	_death_embers()
	_daybreak()
	_enemy_phase_application()
func _battle(roster:Array[String]=["dest_lee"],allies:Array[Vector2i]=[],enemies:Array[Vector2i]=[Vector2i(3,1),Vector2i(6,6)]):
	var b=B.new()
	root.add_child(b)
	b.start_encounter(Vector2i(1,1),enemies,[],[],roster,allies)
	return b
func _ignite(b,id:String,stacks:int)->void:
	b.statuses.apply_status(IGNITION,"dest_lee",id,stacks,2,-1,&"",&"replace")
	var s=b.statuses.get_status(id,IGNITION)
	if s!=null:
		s.enemy_turns_remaining=2
func _sheet()->void:
	_check(C.has_definition("dest_lee"),"Dest Lee registered")
	var s=C.get_definition("dest_lee")
	_check(s.max_health==1400 and s.attack==430 and s.defense==130 and s.magic_resistance==100,"approved panel")
	_check(R.skills_for_character("dest_lee").size()==5,"five ordered slots")
	for sk in R.active_skills_for_character("dest_lee"):
		_check(Runtime.supports(sk.executor_id),"executor exists: "+String(sk.skill_id))
func _blackflame()->void:
	var b=_battle()
	var e=b.get_actor("vanguard_00")
	var hp=e.health
	_check(b.request_skill(&"dest_lee_blackflame_shot","vanguard_00"),"Blackflame resolves")
	_check(e.health<hp,"Blackflame deals damage")
	var s=b.statuses.get_status(e.actor_id,IGNITION)
	_check(s!=null and s.stacks==1 and s.enemy_turns_remaining==2,"Blackflame applies one ignition stack")
	b.queue_free()
func _black_rain()->void:
	var b=_battle()
	var e=b.get_actor("vanguard_00")
	var hp=e.health
	_check(b.request_skill(&"dest_lee_black_rain","",Vector2i(2,1)),"Black Rain aims at empty cell")
	_check(e.health<hp,"Black Rain hits diamond")
	var s=b.statuses.get_status(e.actor_id,IGNITION)
	_check(s!=null and s.stacks==2,"Black Rain fills ignition to two stacks")
	b.queue_free()
func _dot()->void:
	var b=_battle()
	var lee=b.get_actor("dest_lee")
	var a=b.get_actor("vanguard_00")
	var z=b.get_actor("vanguard_01")
	a.magic_resistance=0
	z.magic_resistance=0
	_ignite(b,a.actor_id,1)
	_ignite(b,z.actor_id,2)
	var ah=a.health
	var zh=z.health
	Lee.tick_ignition(b)
	_check(ah-a.health==Math.calculate_raw_damage(lee.attack,0.25),"one stack DOT is 25% ATK")
	_check(zh-z.health==Math.calculate_raw_damage(lee.attack,0.40),"two stack DOT is 40% ATK")
	b.queue_free()
func _city_burn()->void:
	var roster:Array[String]=["dest_lee"]
	var allies:Array[Vector2i]=[]
	var enemies:Array[Vector2i]=[Vector2i(3,1),Vector2i(4,1)]
	var b=_battle(roster,allies,enemies)
	var a=b.get_actor("vanguard_00")
	var z=b.get_actor("vanguard_01")
	a.magic_resistance=0
	z.magic_resistance=0
	_ignite(b,a.actor_id,1)
	var ah=a.health
	var zh=z.health
	_check(b.request_skill(&"dest_lee_city_burn"),"City Burn resolves")
	_check(ah-a.health==Math.calculate_raw_damage(430,1.5),"direct target gets 100% plus 50% splash")
	_check(zh-z.health==Math.calculate_raw_damage(430,0.5),"non-target gets one 50% splash")
	_check(not b.statuses.has_status(a.actor_id,IGNITION),"direct target ignition cleared")
	b.queue_free()
func _death_embers()->void:
	var roster:Array[String]=["dest_lee","sakura"]
	var allies:Array[Vector2i]=[Vector2i(1,2)]
	var enemies:Array[Vector2i]=[Vector2i(2,2),Vector2i(3,2),Vector2i(6,6)]
	var b=_battle(roster,allies,enemies)
	b.set_active_character("sakura")
	var dead=b.get_actor("vanguard_00")
	var near=b.get_actor("vanguard_01")
	near.magic_resistance=0
	dead.health=1
	_ignite(b,dead.actor_id,1)
	var hp=near.health
	_check(b.request_skill(&"sakura_pierce_blossom",dead.actor_id),"Sakura kills ignited enemy with Lee present")
	_check(dead.is_defeated(),"original target defeated")
	_check(hp-near.health==Math.calculate_raw_damage(430,0.8),"Death Embers hits orthogonal neighbour")
	var s=b.statuses.get_status(near.actor_id,IGNITION)
	_check(s!=null and s.stacks==1,"Death Embers ignites survivor")
	b.queue_free()
func _daybreak()->void:
	var b=_battle()
	var lee=b.get_actor("dest_lee")
	var e=b.get_actor("vanguard_00")
	e.magic_resistance=0
	e.max_health=5000
	e.health=5000
	lee.ultimate_energy=5
	var hp=e.health
	_check(b.request_skill(&"dest_lee_daybreak_ends","",Vector2i(1,1)),"Daybreak targets own cell")
	var expected=Math.calculate_raw_damage(430,0.45)*3+Math.calculate_raw_damage(430,0.85)
	_check(hp-e.health==expected,"Daybreak resolves four rounds")
	_check(lee.ultimate_energy==0,"Daybreak spends full energy")
	var s=b.statuses.get_status(e.actor_id,IGNITION)
	_check(s!=null and s.stacks==2,"later rounds refresh ignition")
	b.queue_free()
func _enemy_phase_application()->void:
	var b=_battle()
	var e=b.get_actor("vanguard_00")
	e.magic_resistance=0
	b.phase=b.BattlePhase.ENEMY
	Lee._ignite(b,e,1)
	var hp=e.health
	Lee.tick_ignition(b)
	_check(e.health==hp,"mid-enemy-phase ignition skips current DOT")
	b.statuses.tick_enemy_phase()
	var s=b.statuses.get_status(e.actor_id,IGNITION)
	_check(s!=null and s.enemy_turns_remaining==2,"two full enemy phases remain")
	b.queue_free()
