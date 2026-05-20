extends Node

const CONFIG_FILE := "user://settings.cfg"

const FULLSCREEN := "fullscreen"
const GRAPHICS_QUALITY := "graphics.quality"

@onready var _config := ConfigFile.new()
@onready var _section := "config" if OS.has_feature("release") else "config.debug"

func _ready():
    if _config.load(CONFIG_FILE) != OK:
        self.set_value(FULLSCREEN, true)

func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        _config.save(CONFIG_FILE)

func set_value(property: StringName, value: Variant):
    _config.set_value(_section, property, value)

func get_value(property: StringName) -> Variant:
    return _config.get_value(_section, property)
