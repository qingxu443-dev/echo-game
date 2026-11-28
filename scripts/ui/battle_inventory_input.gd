class_name BattleInventoryInput
extends RefCounted


static func lead_actor(view):
	var level: EncounterDefinition = view._current_level()
	if level != null and not level.character_ids.is_empty():
		return view.controller.actors.get(level.character_ids[0])
	return view.controller.get_active_character()


## CONTRACT: _test_inventory_after_switching
static func handle(view, position: Vector2) -> void:
	var state: RunState = view.run_state
	var action := InventoryView.hit(position, state.backpack.size(), view.inventory_page)
	var lead = lead_actor(view)
	match action:
		InventoryView.ACTION_CLOSE: view.inventory_open = false
		InventoryView.ACTION_PAGE_PREV: view.inventory_page = maxi(0, view.inventory_page - 1)
		InventoryView.ACTION_PAGE_NEXT:
			var pages: int = maxi(1, ceili(float(state.backpack.size()) / InventoryView.PAGE_SIZE))
			view.inventory_page = mini(pages - 1, view.inventory_page + 1)
		InventoryView.ACTION_UNEQUIP_WEAPON, InventoryView.ACTION_UNEQUIP_ARMOR:
			var slot := "weapon" if action == InventoryView.ACTION_UNEQUIP_WEAPON else "armor"
			var message := state.unequip_slot(slot, lead)
			if not message.is_empty(): view.status_message = message
		_:
			if action.begins_with(InventoryView.ACTION_BAG_PREFIX):
				var index := int(action.substr(InventoryView.ACTION_BAG_PREFIX.length()))
				if index < 0 or index >= state.backpack.size(): return
				var kind := str(state.backpack[index].get("kind", ""))
				var actor = lead if kind in ["weapon", "armor"] else view.controller.get_active_character()
				var message := state.use_backpack_item(index, view.controller, actor)
				if lead != null: state.hero_health = lead.health
				if not message.is_empty(): view.status_message = message
				var pages: int = maxi(1, ceili(float(state.backpack.size()) / InventoryView.PAGE_SIZE))
				view.inventory_page = clampi(view.inventory_page, 0, pages - 1)
	view.queue_redraw()
