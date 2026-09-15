extends Control

var game: Node3D
var font: Font = ThemeDB.fallback_font
var layer: Control
var category = "Rifles"
var gold = Color("e9af52")
var blue = Color("8bc9e6")
var paper = Color("eee9dd")
var muted = Color("aeb1ac")
var ink = Color(.035,.045,.05,.93)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(rebuild)
	rebuild()

func _process(_dt: float) -> void:
	queue_redraw()
	if layer:
		layer.visible = game.state == "menu" or game.paused or game.buying or (game.match_over and not game.spectator.in_death_recap())

func txt(text: String, pos: Vector2, size_px: int, color := Color.WHITE) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func center(text: String, x: float, y: float, size_px: int, color := Color.WHITE) -> void:
	var width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	txt(text,Vector2(x-width/2,y),size_px,color)

func panel(rect: Rect2, color := Color(.03,.04,.045,.78), border := false) -> void:
	draw_style_box(style(color,Color(.7,.72,.69,.13) if border else Color.TRANSPARENT),rect)

func style(bg: Color, edge := Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

func button(label: String, rect: Rect2, callback: Callable, highlight := false) -> Button:
	var b = Button.new()
	b.text = label
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",Color("1c211f") if highlight else paper)
	b.add_theme_color_override("font_hover_color",Color("1c211f") if highlight else Color.WHITE)
	b.add_theme_stylebox_override("normal",style(gold if highlight else Color(.08,.1,.1,.9),Color(.6,.65,.65,.2)))
	b.add_theme_stylebox_override("hover",style(Color("f7c56d") if highlight else Color(.19,.22,.22,.98),gold))
	b.add_theme_stylebox_override("pressed",style(Color("c18c35"),gold))
	b.pressed.connect(callback)
	layer.add_child(b)
	return b

func rebuild() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(layer):
		remove_child(layer)
		layer.queue_free()
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	var w = size.x
	var h = size.y
	if game.state == "menu":
		var x = w*.075
		var y = h*.49
		button("CT  /  СПЕЦНАЗ",Rect2(x,y,218,52),func(): game.selected_team="CT"; rebuild(),game.selected_team=="CT")
		button("T  /  АТАКА",Rect2(x+230,y,218,52),func(): game.selected_team="T"; rebuild(),game.selected_team=="T")
		button("ТРЕНИРОВКА   ·   весь арсенал" if game.practice else "КЛАССИКА   ·   экономика",Rect2(x,y+68,448,48),func(): game.practice=not game.practice; rebuild())
		button("НАЧАТЬ ОПЕРАЦИЮ     →",Rect2(x,y+138,448,64),game.start_match,true)
		button("Выйти",Rect2(x,h-80,110,36),func(): get_tree().quit())
	elif game.buying:
		var x = w*.08
		var y = h*.15
		var cats = ["Pistols","SMGs","Rifles","Snipers","Heavy","Equipment"]
		var labels = ["ПИСТОЛЕТЫ","ПП","ВИНТОВКИ","СНАЙПЕРСКИЕ","ТЯЖЁЛОЕ","СНАРЯЖЕНИЕ"]
		for i in cats.size():
			var c: String = cats[i]
			button(labels[i],Rect2(x+i*(w*.84/6),y+42,w*.84/6-7,45),func(): category=c; rebuild(),category==c)
		var items: Array[String] = []
		for id in game.weapon_order:
			if game.weapons[id].category == category: items.append(id)
		if category == "Equipment": items.assign(["armor","kit","zeus","he","smoke","flash","fire","decoy"])
		var columns = 4
		var cw = (w*.84-36)/4
		for i in items.size():
			var id: String = items[i]
			var label = ""
			var available = true
			if game.weapons.has(id):
				var weapon: Dictionary = game.weapons[id]
				label = "%s\n$ %d   ·   %d / %d" % [weapon.name,weapon.price,weapon.mag,weapon.reserve]
				available = game.practice or weapon.team in ["ALL",game.player.team]
				if not available: label += "\nТолько " + weapon.team
			else:
				label = {"armor":"Броня + шлем\n$ 1 000","kit":"Набор сапёра\n$ 400","he":"Осколочная\n$ 300","smoke":"Дымовая\n$ 300","flash":"Световая\n$ 200","fire":"Зажигательная\n$ 400","decoy":"Ложная граната\n$ 50"}[id]
				available = id != "kit" or game.player.team == "CT"
			var b = button(label,Rect2(x+(i%columns)*(cw+12),y+110+floori(float(i)/columns)*102,cw,90),func(): game.buy(id))
			b.disabled = not available
		button("ГОТОВО   [ B / ESC ]",Rect2(w*.68,h*.79,w*.24,52),func(): game.buying=false; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; rebuild(),true)
	elif game.paused or game.match_over:
		button("ПРОДОЛЖИТЬ" if not game.match_over else "ЕЩЁ ОДИН МАТЧ",Rect2(w/2-180,h/2-20,360,54),func():
			if game.match_over: game.start_match()
			else: game.paused=false; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED; rebuild(),true)
		button("ВЫБОР КОМАНДЫ",Rect2(w/2-180,h/2+49,360,48),game.return_menu)
		button("ВЫЙТИ ИЗ ИГРЫ",Rect2(w/2-180,h/2+110,360,48),func(): get_tree().quit())

func _draw() -> void:
	if not game or not game.player: return
	var w = size.x
	var h = size.y
	var p: CharacterBody3D = game.player
	var watching: bool = game.spectator.observing()
	var death_recap: bool = game.spectator.in_death_recap()
	var viewed: Node3D = game.spectator.target if watching else p
	if game.state == "menu":
		# Dark glass keeps the actual live 3D map visible behind the menu.
		panel(Rect2(0,0,w*.48,h),Color(.025,.033,.034,.87))
		draw_rect(Rect2(0,0,w,5),gold)
		var x = w*.075
		txt("LOCAL OPERATION  /  01",Vector2(x,h*.14),16,gold)
		txt("DUST",Vector2(x,h*.28),88,paper)
		txt("STRIKE",Vector2(x,h*.375),88,paper)
		txt("ПЯТЬ ПРОТИВ ПЯТИ. ОДИН РАУНД РЕШАЕТ ВСЁ.",Vector2(x,h*.43),15,muted)
		panel(Rect2(w-318,40,276,90),Color(.03,.045,.05,.65),true)
		txt("DUST  /  ПЕСЧАНЫЙ СЕКТОР",Vector2(w-300,72),16,paper)
		txt("2 точки  ·  9 ботов  ·  34 оружия",Vector2(w-300,103),15,muted)
		txt("WASD  движение     МЫШЬ  обзор     ЛКМ  огонь",Vector2(x,h*.49+240),15,paper)
		txt("B  закупка     R  перезарядка     E  бомба",Vector2(x,h*.49+268),15,muted)
		txt("Локальный прототип на Godot • оригинальные модели Blender",Vector2(x+128,h-56),12,muted)
		txt("Карта Dust II: vrchris · CC BY 4.0    |    Полные лицензии: README.md",Vector2(x,h-22),11,muted)
		txt("F11  ПОЛНЫЙ ЭКРАН",Vector2(w-220,h-38),13,paper)
		return
	if death_recap: draw_rect(Rect2(Vector2.ZERO,size),Color(.09,.015,.01,.20))
	# Match clock and survivor strip.
	panel(Rect2(w/2-118,12,236,76),Color(.03,.04,.045,.85))
	center(str(game.score.CT),w/2-79,46,28,blue)
	center(str(game.score.T),w/2+79,46,28,gold)
	var remaining: float = game.freeze_clock if game.state == "freeze" else game.bomb_clock if game.bomb_state == "planted" else game.round_clock
	var timer = "%d:%02d" % [int(maxf(remaining,0))/60,int(maxf(remaining,0))%60]
	center(timer,w/2,44,24,Color("f27358") if game.bomb_state=="planted" else paper)
	center("РАУНД %02d  /  ДО 6 ПОБЕД" % game.round_number,w/2,72,11,muted)
	for side in ["CT","T"]:
		var n = 0
		for actor in game.actors():
			if actor.team != side: continue
			var xx: float = w/2-155-n*40 if side=="CT" else w/2+127+n*40
			var color: Color = blue if side=="CT" else gold
			panel(Rect2(xx,15,32,38),Color(color,.52 if actor.alive else .1))
			center("●" if actor.alive else "×",xx+16,40,18,color if actor.alive else muted)
			n += 1
	draw_radar(Rect2(24,26,200,200))
	var location = "Точка A" if viewed.position.distance_to(game.site_a)<12 else "Точка B" if viewed.position.distance_to(game.site_b)<12 else "Тоннели" if viewed.position.x < -27 and viewed.position.z > -14 and viewed.position.z < 26 else "Длина A" if viewed.position.x > 28 else "База T" if viewed.position.z > 27 else "База CT" if viewed.position.z < -26 else "Центр"
	txt(location,Vector2(27,251),19,paper)
	txt("$ %d" % p.cash if p.alive else "ВЫ ПОГИБЛИ" if death_recap else "ЗРИТЕЛЬ",Vector2(27,281),25,gold)
	# Kill feed.
	for i in game.killfeed.size():
		var k: Dictionary = game.killfeed[i]
		var killer: String = ("[%s] " % k.killer_team if k.killer_team != "" else "") + k.killer
		var victim: String = "[%s] %s" % [k.victim_team,k.victim]
		var killer_width = font.get_string_size(killer,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var victim_width = font.get_string_size(victim,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var row_width = killer_width + victim_width + 66
		var x: float = w-25-row_width
		var y: float = 113+i*47
		panel(Rect2(x,y,row_width,41),Color(.03,.04,.04,.88))
		txt(killer,Vector2(x+12,y+18),16,blue if k.killer_team=="CT" else gold if k.killer_team=="T" else muted)
		txt("→",Vector2(x+24+killer_width,y+18),16,paper)
		txt(victim,Vector2(x+54+killer_width,y+18),16,blue if k.victim_team=="CT" else gold)
		var detail = "САМОЛИКВИДАЦИЯ" if k.self else "ОГОНЬ ПО СВОИМ" if k.friendly else "В ГОЛОВУ" if k.headshot else "УБИЙСТВО"
		txt(detail,Vector2(x+12,y+33),10,Color("f09580") if k.friendly else muted)
	# Team labels only. Enemies have no through-wall indicators.
	if p.alive:
		for actor in game.bots:
			if not actor.alive or actor.team != p.team: continue
			var point: Vector3 = actor.global_position+Vector3.UP*2.12
			if p.cam.is_position_behind(point): continue
			var screen = p.cam.unproject_position(point)
			if screen.x > 0 and screen.x < w and screen.y > 0 and screen.y < h:
				center("◆",screen.x,screen.y,12,blue if p.team=="CT" else gold)
				if p.position.distance_to(actor.position) < 24: center(actor.nick,screen.x,screen.y-16,12,paper)
	# Crosshair with velocity/recoil spread.
	if p.alive and not game.ui_blocked():
		var c = Vector2(w/2,h/2)
		if p.scoped:
			var radius = h*.44
			for i in 64:
				var a = TAU*i/64.0
				var b = TAU*(i+1)/64.0
				var va = Vector2(cos(a),sin(a))
				var vb = Vector2(cos(b),sin(b))
				draw_colored_polygon(PackedVector2Array([c+va*radius,c+vb*radius,c+vb*w*2,c+va*w*2]),Color(.005,.008,.005,.98))
			draw_circle(c,minf(w,h)*.38,Color(.02,.025,.025,.05))
			draw_line(Vector2(0,c.y),Vector2(w,c.y),Color(.015,.02,.015),1)
			draw_line(Vector2(c.x,0),Vector2(c.x,h),Color(.015,.02,.015),1)
			draw_circle(c,2,Color("d65436"))
		else:
			var gap: float = 5 + Vector2(p.velocity.x,p.velocity.z).length()*1.2 + p.recoil.length()*180
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				draw_line(c+direction*gap,c+direction*(gap+7),Color(.02,.03,.02,.85),4)
				draw_line(c+direction*gap,c+direction*(gap+7),Color("a2e1b3"),2)
		if game.hitmarker > 0:
			for v in [Vector2(-1,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1)]:draw_line(c+v*7,c+v*13,paper,2)
	# Lower tactical HUD.
	panel(Rect2(24,h-102,274,70),Color(.03,.04,.045,.8))
	txt("+",Vector2(43,h-52),35,paper)
	txt(str(int(viewed.hp)),Vector2(80,h-49),36,paper)
	draw_line(Vector2(163,h-87),Vector2(163,h-47),Color(.7,.73,.7,.25))
	txt("◇",Vector2(180,h-53),26,blue)
	txt(str(int(viewed.armor)),Vector2(213,h-51),29,blue)
	draw_rect(Rect2(40,h-41,242,3),Color(.6,.6,.6,.3))
	draw_rect(Rect2(40,h-41,242*maxf(0,viewed.hp)/100,3),gold)
	panel(Rect2(w-309,h-118,285,87),Color(.03,.04,.045,.8))
	var name_label: String = "НОЖ" if p.equip_id == "knife" else game.weapons[p.equip_id].name
	if watching: name_label = "M4A4" if viewed.team == "CT" else "AK-47"
	txt(name_label,Vector2(w-290,h-90),18,paper)
	if watching:
		txt("ПЕРЕЗАРЯДКА" if viewed.reload_left > 0 else "НАБЛЮДЕНИЕ",Vector2(w-290,h-50),18,gold)
	elif p.equip_id != "knife":
		txt(str(p.ammo[p.equip_id][0]),Vector2(w-290,h-48),36,paper)
		txt("/  " + str(p.ammo[p.equip_id][1]),Vector2(w-225,h-49),22,muted)
		if p.reload_left > 0:
			txt("ПЕРЕЗАРЯДКА",Vector2(w-167,h-53),11,gold)
			draw_rect(Rect2(w-290,h-39,248*(1-p.reload_left/p.reload_total),3),gold)
	if p.alive:
		txt("G  %s  ×%d" % [game.utility_names[p.selected_utility],p.utility[p.selected_utility]],Vector2(w-309,h-135),14,gold)
		center("1  ОСНОВНОЕ     2  ПИСТОЛЕТ     3  НОЖ     4  ГРАНАТЫ",w/2,h-34,12,muted)
		center("SHIFT  тихий шаг    CTRL  присесть    SPACE  прыжок    TAB  счёт",w/2,h-15,11,muted)
	else:
		panel(Rect2(w/2-260,h-108,520,80),Color(.025,.035,.04,.88))
		if death_recap:
			center("ИТОГИ ГИБЕЛИ  ·  %d С" % ceili(game.spectator.death_left),w/2,h-76,21,gold)
			center("ПРОБЕЛ — перейти к наблюдению" if game.spectator.death_left <= game.spectator.DEATH_RECAP_SECONDS-game.spectator.SKIP_DELAY else "Камера остаётся на месте гибели",w/2,h-46,13,paper)
		else:
			center("НАБЛЮДЕНИЕ  ·  " + viewed.nick if watching else "ЖИВЫХ СОЮЗНИКОВ НЕ ОСТАЛОСЬ",w/2,h-76,21,gold)
			center("← / →  переключение    ПРОБЕЛ  следующий    TAB  счёт" if watching else "Ожидайте завершения раунда",w/2,h-46,13,paper)
	if game.bomb_carrier == p and game.bomb_state == "carried": txt("▣  БОМБА У ВАС",Vector2(27,311),15,gold)
	if game.bomb_state == "planted": center("БОМБА УСТАНОВЛЕНА",w/2,119,16,Color("f27358"))
	if game.state == "freeze":
		center("ПОДГОТОВКА К РАУНДУ",w/2,h*.28,23,paper)
		center("B — открыть закупку",w/2,h*.28+32,17,gold)
	if game.action_label != "":
		center(game.action_label,w/2,h*.68,19,paper)
		if game.action_progress > 0:
			var duration = 3.2 if game.bomb_state != "planted" else 5.0 if game.defuse_kit else 10.0
			panel(Rect2(w/2-150,h*.68+20,300,6),Color(.1,.1,.1,.8))
			draw_rect(Rect2(w/2-150,h*.68+20,300*game.action_progress/duration,6),gold)
	if game.toast_left > 0:
		center(game.toast,w/2,h*.79,17,paper)
	if game.state == "ended":
		panel(Rect2(w/2-340,h*.24,680,125),Color(.025,.035,.04,.9))
		center(("СПЕЦНАЗ" if game.winner == "CT" else "АТАКА")+" ПОБЕЖДАЕТ",w/2,h*.24+48,30,blue if game.winner=="CT" else gold)
		center(game.win_reason,w/2,h*.24+81,18,paper)
		center("МАТЧ ЗАВЕРШЁН" if game.match_over else "Следующий раунд через %d" % ceili(game.end_clock),w/2,h*.24+107,14,muted)
	if death_recap: draw_death_recap()
	if game.spectator.transition_left > 0:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,game.spectator.transition_left/.18))
	if Input.is_physical_key_pressed(KEY_TAB) and not game.buying: draw_scoreboard()
	if game.hurt_alpha > 0:
		for r in [Rect2(0,0,w,28),Rect2(0,h-28,w,28),Rect2(0,0,28,h),Rect2(w-28,0,28,h)]:draw_rect(r,Color(.65,.035,.02,game.hurt_alpha))
	if game.flash_alpha > 0: draw_rect(Rect2(Vector2.ZERO,size),Color(1,1,.96,game.flash_alpha))
	if game.buying:
		panel(Rect2(0,0,w,h),Color(.015,.025,.03,.87))
		var x = w*.08
		var y = h*.15
		txt("АРСЕНАЛ",Vector2(x,y+17),32,paper)
		txt("$ %d" % p.cash,Vector2(w*.78,y+16),29,gold)
		txt("Тренировка: всё оружие доступно без ограничений" if game.practice else "Снаряжение вашей команды · покупка у базы",Vector2(x,h*.79+22),16,muted)
		txt("Выбрано: "+name_label,Vector2(x,h*.79+49),18,gold)
	elif game.paused:
		panel(Rect2(0,0,w,h),Color(.015,.025,.03,.82))
		center("ПАУЗА",w/2,h/2-95,48,paper)
		center("DUST STRIKE  /  ЛОКАЛЬНАЯ ОПЕРАЦИЯ",w/2,h/2-56,14,gold)
		txt("Мышь: обзор · ПКМ: прицел · F: осмотр оружия · F11: полный экран",Vector2(w/2-335,h/2+205),15,muted)

func draw_death_recap() -> void:
	var info: Dictionary = game.spectator.death_info
	var width = minf(620,size.x-48)
	var x = (size.x-width)/2
	var y = size.y*.46
	panel(Rect2(x,y,width,162),Color(.035,.04,.045,.96),true)
	draw_rect(Rect2(x,y,width,4),Color("cf6556"))
	center("ВЫ ПОГИБЛИ",size.x/2,y+42,30,paper)
	var cause = "Взрыв / урон окружения"
	if info.self:
		cause = "Собственный урон"
	elif info.killer != "":
		cause = ("Огонь по своим: " if info.friendly else "Вас убил: ")+"[%s] %s" % [info.team,info.killer]
	var killer_color: Color = blue if info.team=="CT" else gold if info.team=="T" else muted
	center(cause,size.x/2,y+81,22,killer_color)
	var detail = "Попадание в голову" if info.headshot else ""
	if info.health >= 0 and not info.self:
		detail += ("  ·  " if detail != "" else "")+"У атакующего осталось %d HP" % info.health
	if detail != "": center(detail,size.x/2,y+111,15,muted)
	var next = "Далее — наблюдение за живым союзником" if not game.spectator.candidates().is_empty() else "Живых союзников нет — ожидайте итогов раунда"
	center(next,size.x/2,y+142,14,paper)

func draw_radar(rect: Rect2) -> void:
	var viewed: Node3D = game.spectator.target if game.spectator.observing() else game.player
	panel(rect,Color(.025,.045,.05,.83),true)
	var scale_map = rect.size.x/100.0
	var origin = rect.position+rect.size/2
	if game.classic:
		scale_map = rect.size.x/150.0
		origin += Vector2(8,28)*scale_map
		var vertices: PackedVector3Array = game.nav_mesh.get_vertices()
		for i in game.nav_mesh.get_polygon_count():
			var polygon = PackedVector2Array()
			for index in game.nav_mesh.get_polygon(i):
				var v = vertices[index]
				polygon.append(origin+Vector2(v.x,v.z)*scale_map)
			if polygon.size() >= 3: draw_colored_polygon(polygon,Color(.56,.56,.5,.43))
	for data in game.map_data:
		var p: Array = data.p
		var s: Array = data.s
		if float(p[1])-float(s[1])/2 > 2 or float(p[1])+float(s[1])/2 < .3: continue
		var r = Rect2(origin+Vector2(float(p[0])-float(s[0])/2,float(p[2])-float(s[2])/2)*scale_map,Vector2(s[0],s[2])*scale_map)
		draw_rect(r,Color(.55,.55,.49,.45))
	for data in [[game.site_a,"A"],[game.site_b,"B"]]:
		var at: Vector2 = origin+Vector2(data[0].x,data[0].z)*scale_map
		center(data[1],at.x,at.y+5,14,gold)
	for actor in game.actors():
		if not actor.alive or (actor.team != game.player.team and (not viewed.alive or not game.can_see(viewed,actor))): continue
		var at: Vector2 = origin+Vector2(actor.position.x,actor.position.z)*scale_map
		draw_circle(at,3.5,Color.WHITE if actor==viewed else blue if actor.team=="CT" else gold)
	var at: Vector2 = origin+Vector2(viewed.position.x,viewed.position.z)*scale_map
	var dir = Vector2(-sin(viewed.rotation.y),-cos(viewed.rotation.y))
	draw_line(at,at+dir*12,Color.WHITE,2)
	if game.bomb_state in ["planted","dropped"]:
		var bp: Vector2 = origin+Vector2(game.bomb_position.x,game.bomb_position.z)*scale_map
		draw_rect(Rect2(bp-Vector2(3,3),Vector2(6,6)),Color("ef7155"))

func draw_scoreboard() -> void:
	var w = size.x
	var h = size.y
	var left = w/2-370
	var top = h/2-245
	panel(Rect2(left,top,740,490),Color(.02,.035,.045,.96),true)
	txt("DUST STRIKE   /   СЧЁТ МАТЧА",Vector2(left+28,top+40),22,paper)
	txt("ИГРОК",Vector2(left+30,top+79),12,muted)
	txt("УБИЙСТВА     СМЕРТИ     ЗДОРОВЬЕ",Vector2(left+390,top+79),12,muted)
	var row = 0
	for side in ["CT","T"]:
		for actor in game.actors():
			if actor.team != side: continue
			var y = top+106+row*34
			if actor==game.player: draw_rect(Rect2(left+18,y-22,704,30),Color(.3,.36,.36,.35))
			txt(("Вы" if actor==game.player else actor.nick)+"  ·  "+side,Vector2(left+30,y),17,blue if side=="CT" else gold)
			txt(str(actor.kills),Vector2(left+429,y),17,paper)
			txt(str(actor.deaths),Vector2(left+521,y),17,paper)
			txt(str(int(actor.hp)) if actor.alive else "—",Vector2(left+635,y),17,paper)
			row += 1
