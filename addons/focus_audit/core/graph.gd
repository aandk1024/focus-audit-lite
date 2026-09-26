@tool
extends RefCounted

## Builds the focus graph of a laid-out scene, by asking the engine.
##
## The important idea in this file is that there are two graphs, not one, and
## most menus are only ever tested on the first:
##
##   TAB graph    - find_next_valid_focus() / find_prev_valid_focus().
##                  This walks the whole scene tree in order, so from any
##                  control you eventually reach every other one. It is
##                  almost impossible to strand anything here, which is why
##                  "I tabbed through it and it was fine" proves so little.
##
##   ARROW graph  - find_valid_focus_neighbor(side) on all four sides.
##                  This is geometric: Godot compares the laid-out rectangles
##                  and picks the nearest control in that direction. It is
##                  what a D-pad, a stick and the arrow keys actually use,
##                  and a control can very easily have nothing pointing at
##                  it. A gamepad has no Tab key, so if a button is not in
##                  this graph a controller player cannot press it at all.
##
## Both are read straight out of the engine rather than reimplemented, so the
## answer is the one the game will really give. Everything here needs the
## scene to be inside a tree and settled: the arrow graph is computed from
## rectangles that do not exist until containers have sorted their children.

## Control.FocusMode. Spelled as numbers because FOCUS_ACCESSIBILITY only
## exists from Godot 4.5, and naming it directly would stop this file from
## parsing on 4.4.
const FOCUS_NONE := 0
const FOCUS_CLICK := 1
const FOCUS_ALL := 2
## 4.5+. Reachable by a screen reader, but NOT by keyboard or gamepad - which
## makes it a trap for exactly the check this addon is for.
const FOCUS_ACCESSIBILITY := 3

const SIDES := [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
const SIDE_NAMES := {SIDE_LEFT: "left", SIDE_TOP: "top", SIDE_RIGHT: "right", SIDE_BOTTOM: "bottom"}

## Controls a player is meant to operate. Used to decide whether "cannot be
## focused" is a defect or simply a label doing its job.
static func is_interactive(c: Control) -> bool:
    if c is BaseButton:
        return not (c as BaseButton).disabled
    return (c is LineEdit) or (c is TextEdit) or (c is Slider) or (c is SpinBox) or (c is ItemList) or (c is Tree)


## Reachable by keyboard and gamepad. FOCUS_CLICK is mouse-only and
## FOCUS_ACCESSIBILITY is screen-reader-only; neither can be walked to.
##
## Newer Godot lets an ancestor switch focus off for a whole branch, and then
## a button still reads focus_mode = ALL while the engine will not focus it.
## The effective value is asked for by name, so this file still works on 4.4,
## which has neither the override nor the method.
static func is_keyboard_focusable(c: Control) -> bool:
    if c.has_method("get_focus_mode_with_override"):
        return int(c.call("get_focus_mode_with_override")) == FOCUS_ALL
    return c.focus_mode == FOCUS_ALL


class Graph extends RefCounted:
    ## Control -> true, in tree order.
    var nodes: Array = []
    ## Control -> Array of {"to": Control, "side": int}
    var arrow_out: Dictionary = {}
    ## Control -> Array of Control
    var arrow_in: Dictionary = {}
    ## Control -> Control (or null)
    var tab_next: Dictionary = {}
    ## The control focus starts on, or null when nothing takes it.
    var entry: Control = null
    ## True when the scene itself put focus somewhere, rather than the graph
    ## falling back to "whatever Tab would reach first".
    var had_initial_focus := false

    func out_of(c: Control) -> Array:
        return arrow_out.get(c, [])

    func in_to(c: Control) -> Array:
        return arrow_in.get(c, [])


## Collects the focusable controls and both graphs. `viewport` is where the
## focus owner lives.
static func build(root: Node, viewport: Viewport) -> Graph:
    var g := Graph.new()
    _collect(root, g.nodes)

    # What the scene focused on its own.
    #
    # Read this carefully, because it decides what the finding may claim. In
    # the editor only @tool scripts run, so a grab_focus() sitting in an
    # ordinary _ready() has NOT happened by the time this is asked - the
    # answer here is about the scene as it was saved, not about the running
    # game. Headless, outside the editor, the same code does see it, which is
    # why this difference never showed up in the test suite. The finding says
    # so in its own words rather than claiming the game opens dead.
    if viewport != null:
        var owner := viewport.gui_get_focus_owner()
        if owner != null and g.nodes.has(owner):
            g.entry = owner
            g.had_initial_focus = true
    if g.entry == null and not g.nodes.is_empty():
        # Tab from nothing lands on the first focusable control in tree order,
        # so that is the honest fallback entry point for reachability.
        g.entry = g.nodes[0]

    for c in g.nodes:
        g.arrow_out[c] = []
        g.arrow_in[c] = []

    for c in g.nodes:
        for side in SIDES:
            var target := _neighbor(c, side)
            if target == null or target == c:
                continue
            if not g.nodes.has(target):
                continue
            g.arrow_out[c].append({"to": target, "side": side})
            var inbound: Array = g.arrow_in[target]
            if not inbound.has(c):
                inbound.append(c)
        g.tab_next[c] = _tab_next(c)

    return g


static func _collect(node: Node, out: Array) -> void:
    if not is_instance_valid(node):
        return
    # A hidden branch is not laid out and cannot take focus, so its
    # rectangles are meaningless and Godot will not navigate into it.
    if node is CanvasItem and not (node as CanvasItem).visible:
        return
    if node is Control:
        var c := node as Control
        if c.is_visible_in_tree() and is_keyboard_focusable(c):
            out.append(c)
    for child in node.get_children():
        _collect(child, out)


## The engine's own answer for "where does the D-pad go from here".
##
## One case is answered before asking. When an explicit focus_neighbor path
## does not resolve to a Control, find_valid_focus_neighbor() prints
## "Neighbor focus node path is invalid" as a red engine error - once per bad
## side, per scan, on both 4.4 and 4.7. The buyer sees a wall of red in the
## Output panel and reasonably concludes the addon is broken, when in fact it
## is doing its job: dead_neighbors() reports exactly these paths as a
## finding, in words, in the report where they belong.
##
## So the path is resolved here first, and the engine is not asked when the
## answer is already known to be "nowhere". Anything else - a path that does
## resolve to a Control, but one that happens to be hidden or unfocusable -
## is left to the engine, because it walks on from there and its answer is
## the one the game will give.
static func _neighbor(c: Control, side: int) -> Control:
    if not c.has_method("find_valid_focus_neighbor"):
        return null
    if c.has_method("get_focus_neighbor"):
        var path: NodePath = c.call("get_focus_neighbor", side)
        if not path.is_empty():
            var target := c.get_node_or_null(path)
            if target == null or not (target is Control):
                return null
    var n = c.call("find_valid_focus_neighbor", side)
    if n is Control:
        return n
    return null


static func _tab_next(c: Control) -> Control:
    if not c.has_method("find_next_valid_focus"):
        return null
    var n = c.call("find_next_valid_focus")
    if n is Control:
        return n
    return null


## Everything reachable from `from` by following arrow edges.
static func reachable_from(g: Graph, from: Control) -> Dictionary:
    var seen := {}
    if from == null:
        return seen
    var queue: Array = [from]
    seen[from] = true
    while not queue.is_empty():
        var cur: Control = queue.pop_front()
        for e in g.out_of(cur):
            var nxt: Control = e["to"]
            if not seen.has(nxt):
                seen[nxt] = true
                queue.append(nxt)
    return seen


## Everything that can reach `to` by following arrow edges - the same walk on
## the reversed graph. Used to tell "you can get there" from "you can get
## back", which are different failures and need different words.
static func can_reach(g: Graph, to: Control) -> Dictionary:
    var seen := {}
    if to == null:
        return seen
    var queue: Array = [to]
    seen[to] = true
    while not queue.is_empty():
        var cur: Control = queue.pop_front()
        for prev in g.in_to(cur):
            if not seen.has(prev):
                seen[prev] = true
                queue.append(prev)
    return seen


## A focus_neighbor_* that was set by hand but does not lead anywhere usable.
## Godot silently ignores these, so nothing tells you the path went stale
## when a node was renamed or moved.
static func dead_neighbors(c: Control) -> Array:
    var out: Array = []
    if not c.has_method("get_focus_neighbor"):
        return out
    for side in SIDES:
        var path: NodePath = c.call("get_focus_neighbor", side)
        if path.is_empty():
            continue
        var target := c.get_node_or_null(path)
        var why := ""
        if target == null:
            why = "no node at that path"
        elif not (target is Control):
            why = "%s is not a Control" % target.get_class()
        elif not (target as Control).is_visible_in_tree():
            why = "%s is not visible" % (target as Control).name
        elif not is_keyboard_focusable(target as Control):
            why = "%s cannot take keyboard focus" % (target as Control).name
        if why != "":
            out.append({"side": side, "path": String(path), "why": why})
    return out
