extends Node
## 현지화 검사: 한국어·영어·일본어 — 번역 누락, 폰트 글리프(글자 깨짐), 메뉴 글자 잘림
var passed := 0
var failed := 0

func check(c: bool, name: String, info := "") -> void:
	if c:
		passed += 1
		print("  PASS  ", name, ("  (" + info + ")") if info != "" else "")
	else:
		failed += 1
		print("  FAIL  ", name, "  ", info)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("== i18n tests ==")
	var f := FileAccess.open("res://data/i18n/ui.csv", FileAccess.READ)
	var header := f.get_csv_line()
	var keys: Array = []
	var missing := {"en": 0, "ja": 0}
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 4:
			continue
		keys.append(row[0])
		if row[2].strip_edges() == "":
			missing.en += 1
		if row[3].strip_edges() == "":
			missing.ja += 1
	check(keys.size() > 150 and missing.en == 0 and missing.ja == 0, "translations: ko/en/ja rows complete", "%d keys" % keys.size())
	var font: Font = load("res://assets/fonts/NotoSansKR-Regular-subset.otf")
	check(font.fallbacks.size() > 0, "fonts: Japanese fallback attached to Korean UI font")
	for loc in ["ko", "en", "ja"]:
		GameSettings.set_value(&"text_language", loc)
		var bad := []
		for k in keys:
			var s := tr(k)
			for ch in s:
				var c := ch.unicode_at(0)
				if c < 32 or ch == " ":
					continue
				var ok := font.has_char(c)
				for fb in font.fallbacks:
					ok = ok or (fb as Font).has_char(c)
				if not ok and not bad.has(ch):
					bad.append(ch)
		check(bad.is_empty(), "fonts[%s]: every translated glyph renders" % loc, "missing: " + "".join(bad.slice(0, 20)))
		check(tr("새 게임") != "" and (loc == "ko" or tr("새 게임") != "새 게임"), "translations[%s]: menu text switches language" % loc, tr("새 게임"))
		check(DialogueDB.text_of("PRO_E03_TAPE_1") != "", "dialogue[%s]: subtitle text" % loc, DialogueDB.text_of("PRO_E03_TAPE_1"))
		# 메뉴 잘림: 타이틀·일시정지·설정 화면을 만들어 글자 폭이 컨테이너를 넘는지 확인
		var root := Control.new()
		root.size = Vector2(1280, 720)
		add_child(root)
		var title: CanvasLayer = load("res://scripts/ui/title_screen.gd").new()
		add_child(title)
		var settings: Control = load("res://scripts/ui/settings_menu.gd").new()
		root.add_child(settings)
		await get_tree().process_frame
		await get_tree().process_frame
		var clipped := []
		for tab in 4:
			settings._show_tab(tab)
			await get_tree().process_frame
			await get_tree().process_frame
			for c in settings.find_children("*", "Label", true, false) + title.find_children("*", "Label", true, false):
				var l := c as Label
				if not l.is_visible_in_tree() or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
					continue
				var need := l.get_theme_font("font").get_string_size(tr(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
				if need > l.size.x + 2.0 and l.size.x > 0:
					clipped.append("%s(%d>%d)" % [l.text.substr(0, 14), need, l.size.x])
		check(clipped.is_empty(), "layout[%s]: no clipped menu text (1280x720)" % loc, ", ".join(clipped.slice(0, 6)))
		title.queue_free()
		root.queue_free()
		await get_tree().process_frame
	GameSettings.set_value(&"text_language", "ko")
	print("== %d passed, %d failed ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
