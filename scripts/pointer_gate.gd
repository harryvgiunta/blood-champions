extends Node
## Who owns the mouse.
##
## Godot warps the cursor to the middle of the window every time a process
## switches into `MOUSE_MODE_CAPTURED` - focused or not - and drops the capture
## when the window loses focus. A scene that writes the mode itself therefore
## fights the engine frame after frame: an instance in the background keeps
## pulling the desktop's pointer into itself and pinning it there. Several
## instances can be up on one desktop (the game, a playtest lab, an agent's
## verification run), so capture is a privilege handed out here, not a mode any
## scene picks.
##
## Contract:
##   * the process starts released and capture is refused until the player has
##     clicked in this window - a window that merely comes up never moves the
##     pointer;
##   * capture is refused while this window is not the focused one, and losing
##     focus releases the pointer on the spot;
##   * `Esc` while captured gives the pointer back until the next click (it is
##     also the key that closes a page, so it is always the way out);
##   * `--no-mouse-capture`, `IRONWOOD_MOUSE_CAPTURE=0`, and every `--headless`
##     run never capture at all: an unattended run cannot take the mouse.
##
## The policy is static, so tests that compile this file before the autoloads
## exist can read it; the autoload `PointerWatch` is the node in the tree that
## feeds it input and focus (`preload` this script as `PointerGate`, the same way
## the scenes preload `Perf`).
##
## Callers write `wanted(panel_open)` every frame they would otherwise capture,
## and use `capture()`/`release()` for the one-off transitions (a page opening
## or closing). All of them are refused by a no-capture process.

const NO_CAPTURE_ARG := "--no-mouse-capture"
const NO_CAPTURE_ENV := "IRONWOOD_MOUSE_CAPTURE"
const OFF_WORDS := ["0", "false", "no", "off"]

## False for an unattended run: nothing here writes the mouse mode.
static var enabled := true
## The player has clicked in this window. Nothing is captured before that, so a
## launch that only comes up leaves the desktop's cursor where it was.
static var armed := false
## True in a capture tool: the frame is drawn as if the pointer were captured
## (the HUD's crosshair), with no input session and no cursor warp behind it.
static var preview_aim := false


func _enter_tree() -> void:
	configure()
	set_process_input(true)


func _input(event: InputEvent) -> void:
	handle_input(event)


func _notification(what: int) -> void:
	handle_notification(what)


## Read this process's switches. Called by the autoload before any scene runs;
## idempotent, so a test may call it again after changing the environment.
static func configure() -> void:
	var off := DisplayServer.get_name() == "headless"
	for args in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		if args.has(NO_CAPTURE_ARG):
			off = true
	if OS.get_environment(NO_CAPTURE_ENV).strip_edges().to_lower() in OFF_WORDS:
		off = true
	enabled = not off
	armed = false


## A click in this window is the engagement that lets it take the pointer.
## `Esc` while captured is the engagement ending: the pointer is handed back
## and stays free until the next click, on any screen.
static func handle_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		armed = true
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		armed = false
		release()


## A window that is no longer the one in front has no business holding the
## pointer; the scene asks again next frame and is refused until focus returns.
static func handle_notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release()


## The mode the caller should hold: `CAPTURED` only while capturing is allowed,
## `VISIBLE` for a page or a refused capture.
static func wanted(panel_open: bool) -> int:
	if panel_open or not can_capture():
		return Input.MOUSE_MODE_VISIBLE
	return Input.MOUSE_MODE_CAPTURED


## Take the pointer if this window may have it. Returns whether it now does.
static func capture() -> bool:
	if not can_capture():
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true


## Give the pointer back. Never refused: releasing is always allowed.
static func release() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Whether the player is aiming: the real capture, or a capture tool framing the
## game's own look. Everything else (mouse look, the log's sample) reads the
## real mode.
static func aiming() -> bool:
	return preview_aim or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Whether a capture request made right now would be honoured.
static func can_capture() -> bool:
	if not enabled or not armed:
		return false
	return DisplayServer.window_is_focused()
