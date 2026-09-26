@tool
extends RefCounted

## The checks. Each one is a question asked of the engine about a scene that
## has actually been built and laid out, and each finding names the control
## and the reason, so it can be argued with rather than merely trusted.

const Graph := preload("res://addons/focus_audit/core/graph.gd")


class Finding extends RefCounted:
    var scene: String = ""
    var node_path: String = ""
    var node_class: String = ""
    ## "no_initial_focus" | "not_keyboard_focusable" | "accessibility_only"
    ## | "unreachable_by_pad" | "pad_dead_end" | "pad_one_way"
    ## | "dead_focus_neighbor"
    var kind: String = ""
    var detail: String = ""
    ## Extra context that is not the node and not the reason - currently the
    ## broken NodePath and why it is broken.
    var note: String = ""
    var text: String = ""

    func _head() -> String:
        if node_path == "":
            return "%s :: " % scene
        return "%s :: %s (%s) " % [scene, node_path, node_class]

    func _shown() -> String:
        if text == "":
            return ""
        var s := text.substr(0, 40)
        if text.length() > 40:
            s += "…"
        # Backslash first, or the escapes written next would be doubled.
        s = s.replace("\\", "\\\\").replace("\"", "\\\"")
        s = s.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
        return " - \"%s\"" % s

    func to_line() -> String:
        match kind:
            "no_initial_focus":
                return _head() + ("nothing has focus when this screen opens, but %s can take it - a gamepad player sees a dead screen. "
                    + "Checked as saved: the editor does not run ordinary scripts, so a grab_focus() in _ready() is not counted here") % detail
            "not_keyboard_focusable":
                return _head() + "cannot be focused (focus_mode is %s), so it is mouse-only%s" % [detail, _shown()]
            "accessibility_only":
                return _head() + "focus_mode is ACCESSIBILITY - a screen reader reaches it, a keyboard or gamepad cannot%s" % _shown()
            "unreachable_by_pad":
                return _head() + "no arrow or D-pad direction leads here from %s%s" % [detail, _shown()]
            "pad_dead_end":
                return _head() + "no arrow or D-pad direction leads out of here - focus gets stuck%s" % _shown()
            "pad_one_way":
                return _head() + "reachable, but no arrow or D-pad route leads back to %s%s" % [detail, _shown()]
            "dead_focus_neighbor":
                return _head() + "focus_neighbor_%s is set but goes nowhere: %s%s" % [detail, note, _shown()]
        return _head() + kind


const TEXT_PROPS := ["text", "placeholder_text"]


class Options extends RefCounted:
    ## Report interactive controls that no keyboard or gamepad can reach.
    var check_focusable := true
    ## Report controls stranded in the arrow graph.
    var check_reachability := true
    ## Report screens that open with nothing focused.
    var check_initial_focus := true
    ## Report focus_neighbor paths that lead nowhere.
    var check_neighbors := true
    ## Report controls you can arrive at but cannot leave in the direction
    ## you came from. Noisier than the rest, so it can be switched off.
    var check_one_way := true


class Inspector extends RefCounted:
    var opts: Options = null

    func _init(options: Options = null) -> void:
        opts = options if options != null else Options.new()

    func inspect(root: Node, ctx: Dictionary, out: Array) -> void:
        var scene := String(ctx.get("scene", ""))
        var viewport = ctx.get("viewport", null)
        var g = Graph.build(root, viewport)

        if opts.check_focusable:
            _check_focusable(root, root, scene, out)

        if opts.check_initial_focus and not g.had_initial_focus and not g.nodes.is_empty():
            var f := Finding.new()
            f.scene = scene
            f.kind = "no_initial_focus"
            f.detail = "%d control(s)" % g.nodes.size()
            out.append(f)

        if opts.check_neighbors:
            _check_neighbors(root, root, scene, out)

        if opts.check_reachability and g.nodes.size() > 1:
            _check_reachability(g, root, scene, out)

    ## A control a player is meant to press, that no keyboard or gamepad can
    ## put focus on. Godot's defaults are fine here - this only fires when
    ## focus_mode was changed, which is usually done to stop the focus ring
    ## being drawn and rarely done knowing what it costs.
    func _check_focusable(node: Node, root: Node, scene: String, out: Array) -> void:
        if not is_instance_valid(node):
            return
        if node is CanvasItem and not (node as CanvasItem).visible:
            return
        if node is Control:
            var c := node as Control
            if c.is_visible_in_tree() and Graph.is_interactive(c) and not Graph.is_keyboard_focusable(c):
                var f := _make(scene, root, c, "", "")
                if c.focus_mode == Graph.FOCUS_ACCESSIBILITY:
                    f.kind = "accessibility_only"
                else:
                    f.kind = "not_keyboard_focusable"
                    f.detail = "NONE" if c.focus_mode == Graph.FOCUS_NONE else "CLICK"
                out.append(f)
        for child in node.get_children():
            _check_focusable(child, root, scene, out)

    func _check_neighbors(node: Node, root: Node, scene: String, out: Array) -> void:
        if not is_instance_valid(node):
            return
        if node is CanvasItem and not (node as CanvasItem).visible:
            return
        if node is Control:
            var c := node as Control
            for bad in Graph.dead_neighbors(c):
                var f := _make(scene, root, c, "dead_focus_neighbor", String(Graph.SIDE_NAMES[bad["side"]]))
                f.note = "%s (%s)" % [bad["path"], bad["why"]]
                out.append(f)
        for child in node.get_children():
            _check_neighbors(child, root, scene, out)

    func _check_reachability(g, root: Node, scene: String, out: Array) -> void:
        var entry: Control = g.entry
        if entry == null:
            return
        var entry_name := String(root.get_path_to(entry))
        var forward = Graph.reachable_from(g, entry)
        var backward = Graph.can_reach(g, entry)

        for c in g.nodes:
            if c == entry:
                continue
            if not forward.has(c):
                var f := _make(scene, root, c, "unreachable_by_pad", entry_name)
                out.append(f)
                continue
            if g.out_of(c).is_empty():
                out.append(_make(scene, root, c, "pad_dead_end", ""))
                continue
            if opts.check_one_way and not backward.has(c):
                out.append(_make(scene, root, c, "pad_one_way", entry_name))

    func _make(scene: String, root: Node, c: Control, kind: String, detail: String) -> Finding:
        var f := Finding.new()
        f.scene = scene
        f.node_path = String(root.get_path_to(c))
        f.node_class = c.get_class()
        f.kind = kind
        f.detail = detail
        for prop in TEXT_PROPS:
            if prop in c:
                var v = c.get(prop)
                if v is String and String(v).strip_edges() != "":
                    f.text = String(v)
                    break
        return f
