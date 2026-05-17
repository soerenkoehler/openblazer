extends Node

const CONFIG_FILE := "user://settings.cfg"

const FULLSCREEN := "fullscreen"
const GRAPHICS_QUALITY := "graphics.quality"

@onready var config := ConfigFile.new()
@onready var section := "config" if OS.has_feature("release") else "config.debug"

func _ready():
    if config.load(CONFIG_FILE) != OK:
        self.set(FULLSCREEN, true)

func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        config.save(CONFIG_FILE)

func set_value(property: StringName, value: Variant):
    config.set_value(section, property, value)

func get_value(property: StringName) -> Variant:
    return config.get_value(section, property)
