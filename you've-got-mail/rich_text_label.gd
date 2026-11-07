extends RichTextLabel

func _ready() -> void:
	_update_text()

func _process(_delta: float) -> void:
	_update_text()

func _update_text() -> void:
	text = "%s Crypto" % Global.GlobalCrypto
