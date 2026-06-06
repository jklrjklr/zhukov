extends Object


func test_addition() -> void:
	var result := 2 + 2
	assert(result == 4, "2 + 2 should equal 4")


func test_string_concat() -> void:
	var s := "hello" + " " + "world"
	assert(s == "hello world", "string concat failed")
