@tool
extends VBoxContainer

## The dock. A thin skin: it reads the checkboxes, calls core/, and prints.
## No rule lives here, so every rule stays testable without an editor.

const Audit := preload("res://addons/focus_audit/core/audit.gd")
const Checks := preload("res://addons/focus_audit/core/checks.gd")
const Report := preload("res://addons/focus_audit/core/report.gd")
const Stage := preload("res://addons/focus_audit/core/stage.gd")

const MD_PATH := "res://focus_audit_report.md"
const JSON_PATH := "res://focus_audit_report.json"

@onready var _log: RichTextLabel = $Log

var _busy := false
## The last run, kept so the export buttons write what the buyer just saw
## rather than silently re-running with whatever the checkboxes say now.
var _last: Object = null
var _last_opts: Object = null


func _ready() -> void:
	$CheckOpen.pressed.connect(_on_check_open)
	_say("Ready. Open a saved scene and press \"Check open scene\".")
	_lite_note()
	$CheckAll.queue_free()
	$ExportRow.queue_free()


## Node names and control text are arbitrary. Printed raw into a bbcode
## label, a "[" turns the rest of the line into a tag and the report silently
## loses characters.
func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _say(s: String) -> void:
	if _log != null:
		_log.append_text(_esc(s) + "\n")


func _options() -> Object:
	var o = Checks.Options.new()
	o.check_focusable = $Focusable.button_pressed
	o.check_reachability = $Reach.button_pressed
	o.check_initial_focus = $Initial.button_pressed
	o.check_neighbors = $Neighbors.button_pressed
	o.check_one_way = $OneWay.button_pressed
	return o


## Every button goes through this. A run takes real frames, and a second
## press part way through would interleave two sets of findings into one
## report - which reads as a result rather than as a bug.
func _refuse_while_busy() -> bool:
	if _busy:
		_say("Still checking - wait for the current run to finish.")
		return true
	return false



func _on_check_open() -> void:
	if _refuse_while_busy():
		return
	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root == null or root.scene_file_path == "":
		_say("No saved scene is open. Open a scene and save it first.")
		return
	await _run(PackedStringArray([root.scene_file_path]))


func _run(scenes: PackedStringArray) -> void:
	_busy = true
	var opts := _options()
	_say("Checking %d scene(s)…" % scenes.size())
	var res = await Audit.run(scenes, self, opts)
	_busy = false
	_last = res
	_last_opts = opts

	for s in res.skipped:
		_say("  could not measure: " + s)
	for line in Report.to_lines(res.findings):
		_say(line)
	_say(Report.summary(res.findings, res.scenes_checked, res.ms))
	if not res.skipped.is_empty():
		_say("%d scene(s) were not measured - they are not covered by the counts above." % res.skipped.size())

## Lite: say once, in the dock itself, what the full version adds and where it is.
func _lite_note() -> void:
	_say("Focus Audit Lite. The full version adds: Check all scenes in one press; Markdown and JSON reports (pinned schema for a build server). https://theidlehands.itch.io/focus-audit")
