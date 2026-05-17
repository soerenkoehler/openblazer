extends Node3D

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("full_screen"):
        if super.get_window().mode == Window.MODE_FULLSCREEN:
            super.get_window().mode = Window.MODE_WINDOWED
        else:
            super.get_window().mode = Window.MODE_FULLSCREEN
