extends Node

var GlobalCrypto := 0
var GlobalWaves := 0
var GlobalServerHealth := 100
var GlobalMonsterAmount := 0
var first_antivirus_placed := false
var gameplay_paused := false

func reset_run_state() -> void:
	GlobalCrypto = 0
	GlobalWaves = 0
	GlobalServerHealth = 100
	GlobalMonsterAmount = 0
	first_antivirus_placed = false
	gameplay_paused = false
	

func can_afford(amount: int) -> bool:
	return amount <= 0 or GlobalCrypto >= amount

func spend_crypto(amount: int) -> bool:
	if amount <= 0:
		return true
	if GlobalCrypto < amount:
		return false
	GlobalCrypto -= amount
	return true

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if GlobalServerHealth <= 0:
		GlobalServerHealth=1
		get_tree().change_scene_to_file("res://death.tscn")
