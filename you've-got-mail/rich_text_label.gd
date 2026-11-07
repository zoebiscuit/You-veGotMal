extends RichTextLabel

func _ready() -> void:
<<<<<<< Updated upstream:you've-got-mail/rich_text_label.gd
	pass
		 # Replace with function body.
=======
	_update_text()
>>>>>>> Stashed changes:you've-got-mail/text_edit_2.gd

func _process(_delta: float) -> void:
	_update_text()

<<<<<<< Updated upstream:you've-got-mail/rich_text_label.gd
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	text = str(Global.GlobalCrypto) + " Crypto"
=======
func _update_text() -> void:
	text = "%s Crypto" % Global.GlobalCrypto
>>>>>>> Stashed changes:you've-got-mail/text_edit_2.gd
