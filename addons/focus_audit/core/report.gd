@tool
extends RefCounted

## Turns findings into the three shapes a buyer needs: a summary for the dock,
## Markdown for a ticket, and JSON a build server can fail a pipeline on.
##
## The JSON shape is a contract. It is versioned and its keys are pinned by
## the test suite, because once it is wired into CI a renamed field is a
## broken build rather than a cosmetic change.

const SCHEMA_VERSION := 1

## A control a player must press but cannot reach is a fail: the game is
## unplayable without a mouse. A one-way route is a warning - awkward, and
## sometimes deliberate.
const SEVERITY := {
    "not_keyboard_focusable": "fail",
    "accessibility_only": "fail",
    "unreachable_by_pad": "fail",
    "pad_dead_end": "fail",
    "dead_focus_neighbor": "fail",
    "no_initial_focus": "warn",
    "pad_one_way": "warn",
}

const KIND_LABEL := {
    "not_keyboard_focusable": "Mouse-only control",
    "accessibility_only": "Screen-reader-only control",
    "unreachable_by_pad": "Cannot be reached with a D-pad",
    "pad_dead_end": "Focus gets stuck here",
    "dead_focus_neighbor": "focus_neighbor points nowhere",
    "no_initial_focus": "Screen opens with nothing focused",
    "pad_one_way": "No route back",
}

const KIND_ORDER := [
    "not_keyboard_focusable", "accessibility_only", "unreachable_by_pad",
    "pad_dead_end", "dead_focus_neighbor", "no_initial_focus", "pad_one_way",
]


static func severity_of(kind: String) -> String:
    return String(SEVERITY.get(kind, "warn"))


static func counts(findings: Array) -> Dictionary:
    var out := {"fail": 0, "warn": 0, "total": 0}
    for f in findings:
        var s := severity_of(f.kind)
        out[s] = int(out.get(s, 0)) + 1
        out["total"] = int(out["total"]) + 1
    return out


static func by_kind(findings: Array) -> Dictionary:
    var out := {}
    for f in findings:
        var k: String = f.kind
        if not out.has(k):
            out[k] = []
        out[k].append(f)
    return out


static func to_lines(findings: Array) -> PackedStringArray:
    var out := PackedStringArray()
    var groups := by_kind(findings)
    for k in KIND_ORDER:
        if not groups.has(k):
            continue
        var list: Array = groups[k]
        out.append("%s (%d)" % [KIND_LABEL.get(k, k), list.size()])
        for f in list:
            out.append("  " + f.to_line())
    # A kind added to checks.gd but not registered here would otherwise
    # vanish from every report.
    for k in groups.keys():
        if KIND_ORDER.has(k):
            continue
        var extra: Array = groups[k]
        out.append("%s (%d)" % [KIND_LABEL.get(k, k), extra.size()])
        for f in extra:
            out.append("  " + f.to_line())
    return out


static func summary(findings: Array, scenes_checked: int, ms: int) -> String:
    var c := counts(findings)
    if c["total"] == 0:
        return "%d scene(s) checked in %dms - nothing to report" % [scenes_checked, ms]
    return "%d scene(s) checked in %dms - %d fail, %d warn" % [
        scenes_checked, ms, c["fail"], c["warn"]]





## Removes a temporary file after a failure. Never touches anything else.
static func _discard(tmp: String) -> void:
    var d := DirAccess.open(tmp.get_base_dir())
    if d != null and d.file_exists(tmp.get_file()):
        d.remove(tmp.get_file())
