extends Control

@export var playfield_scene: PackedScene = preload("res://playfield.tscn")

@onready var viewport_1: SubViewport = $VBoxContainer/Player1/SubViewport
@onready var viewport_2: SubViewport = $VBoxContainer/Player2/SubViewport

func _ready() -> void:
    var playfield: Node = playfield_scene.instantiate()
    viewport_1.add_child(playfield)
    viewport_2.world_3d = viewport_1.world_3d

    configure_remote_transform(playfield, "Player1", viewport_1)
    configure_remote_transform(playfield, "Player2", viewport_2)

    set_fullscreen(Config.get_value(Config.FULLSCREEN))

func configure_remote_transform(playfield: Node, player: String, viewport: SubViewport) -> void:
    var camera_position := playfield.get_node("%s/CameraPosition" % player)
    var destination_camera := viewport.get_node("Camera3D")

    var remote_transform := RemoteTransform3D.new()
    remote_transform.remote_path = destination_camera.get_path()
    remote_transform.update_position = true
    remote_transform.update_rotation = true
    remote_transform.update_scale = false

    camera_position.add_child(remote_transform)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("fullscreen", false, true):
        set_fullscreen(not Config.get_value(Config.FULLSCREEN))

func set_fullscreen(fullscreen: bool):
    super.get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
    Config.set_value(Config.FULLSCREEN, fullscreen)
