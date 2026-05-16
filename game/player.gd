@tool
extends RigidBody3D

@export var cabin_color: Color = Color.WHITE:
	set(value):
		cabin_color = value
		_update_properties()

@export var cabin_texture: Texture2D:
	set(value):
		cabin_texture = value
		_update_properties()

@export var base_color: Color = Color.WHITE:
	set(value):
		base_color = value
		_update_properties()

@export var base_texture: Texture2D:
	set(value):
		base_texture = value
		_update_properties()

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_properties()

func _update_properties() -> void:
	_update_albedo("Droid/Cabin", cabin_color, cabin_texture)
	_update_albedo("Droid/Base", base_color, base_texture)

func _update_albedo(path: String, color: Color, texture: Texture2D) -> void:
	var mesh_node = get_node_or_null(path) as MeshInstance3D
	if mesh_node:
		var material = mesh_node.material_override as StandardMaterial3D
		if not material:
			material = StandardMaterial3D.new()
			mesh_node.material_override = material

		# Assign the forwarded properties
		material.albedo_color = color
		material.albedo_texture = texture
