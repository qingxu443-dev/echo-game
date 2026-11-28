class_name DestLeeSkillCatalog
extends RefCounted
const S=preload("res://scripts/battle/skill_definition.gd")
const C=preload("res://scripts/battle/character_definition.gd")
static func create_skills()->Array[SkillDefinition]:
	var out:Array[SkillDefinition]=[]
	out.append(_make(&"dest_lee_blackflame_shot","黑焰射击","消耗 1 AP；对曼哈顿距离 2 格内的一名可见敌人造成 80% ATK 法术伤害，命中后施加 1 层引燃。",1,S.TARGET_ACTOR,1,2,S.DAMAGE_MAGICAL,0.8,&"dest_lee_blackflame_shot",C.SLOT_NORMAL))
	var p:=S.new()
	p.skill_id=&"dest_lee_death_embers"
	p.display_name_zh="死亡余烬"
	p.description_zh="被动：带有引燃的敌人被友方直接击杀时，在其死亡位置引发连锁爆炸。"
	p.ap_cost=0
	p.target_mode=S.TARGET_SELF
	p.is_passive=true
	p.slot=C.SLOT_PASSIVE
	out.append(p)
	var rain:=_make(&"dest_lee_black_rain","黑雨","消耗 1 AP；指定距离 5 格内的地格，对曼哈顿半径 2 格内可见敌人造成 20% ATK 法术伤害，并将其引燃补至 2 层。",1,S.TARGET_CELL,0,5,S.DAMAGE_MAGICAL,0.2,&"dest_lee_black_rain",C.SLOT_ACTIVE_ONE)
	rain.shape=S.SHAPE_DIAMOND
	rain.shape_radius=2
	out.append(rain)
	out.append(_make(&"dest_lee_city_burn","焚城指令","消耗 2 AP；引爆全场至少拥有 1 层引燃的敌人。引爆目标受到 100% ATK，爆炸范围内敌人受到最多一次 50% ATK 溅射；结算后清除引爆目标的引燃。",2,S.TARGET_SELF,0,0,S.DAMAGE_NONE,0.0,&"dest_lee_city_burn",C.SLOT_ACTIVE_TWO))
	var u:=_make(&"dest_lee_daybreak_ends","白昼终焉","消耗 2 AP 与全部 5 点终极能量；指定距离 5 格内的地格，连续轰炸曼哈顿半径 2 格区域四轮（45% / 45% / 45% / 85% ATK），每轮命中后施加或刷新 1 层引燃。",2,S.TARGET_CELL,0,5,S.DAMAGE_MAGICAL,2.2,&"dest_lee_daybreak_ends",C.SLOT_ULTIMATE)
	u.hits=4
	u.hit_multipliers=[0.45,0.45,0.45,0.85]
	u.shape=S.SHAPE_DIAMOND
	u.shape_radius=2
	out.append(u)
	return out
static func _make(id:StringName,label:String,desc:String,ap_cost:int,target:StringName,min_r:int,max_r:int,damage:StringName,mult:float,executor:StringName,slot:StringName)->SkillDefinition:
	var sk:=S.new()
	sk.skill_id=id
	sk.display_name_zh=label
	sk.description_zh=desc
	sk.ap_cost=ap_cost
	sk.target_mode=target
	sk.min_range=min_r
	sk.max_range=max_r
	sk.damage_type=damage
	sk.damage_multiplier=mult
	sk.executor_id=executor
	sk.slot=slot
	return sk
