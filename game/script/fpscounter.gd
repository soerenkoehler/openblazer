extends Label

@export var update_interval: float = 0.5
var update_timer: float = 0.0

func _process(delta: float) -> void:
    update_timer += delta
    if update_timer >= update_interval:
        text = "FPS: %.1f" % Engine.get_frames_per_second()
        update_timer = 0.0
