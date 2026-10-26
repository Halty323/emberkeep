@tool
extends SceneTree
## CLI helper: update only Android SDK/JDK editor paths before exporting.
func _initialize() -> void:
	call_deferred("configure")

func configure() -> void:
	# Let editor startup and its initial filesystem scan finish before quitting.
	await create_timer(0.3).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem != null and filesystem.is_scanning():
		await create_timer(0.05).timeout
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		push_error("Run this helper with --headless --editor --script.")
		quit(1)
		return
	var sdk := OS.get_environment("EMBERKEEP_ANDROID_SDK")
	var jdk := OS.get_environment("EMBERKEEP_JAVA_SDK")
	var keystore := OS.get_environment("EMBERKEEP_DEBUG_KEYSTORE")
	if sdk.is_empty() or jdk.is_empty() or keystore.is_empty():
		push_error("Missing Emberkeep Android export environment paths.")
		quit(1)
		return
	settings.set_setting("export/android/android_sdk_path", sdk)
	settings.set_setting("export/android/java_sdk_path", jdk)
	settings.set_setting("export/android/debug_keystore", keystore)
	settings.set_setting("export/android/debug_keystore_user", "androiddebugkey")
	settings.set_setting("export/android/debug_keystore_pass", "android")
	var error := ResourceSaver.save(settings, settings.resource_path)
	if error != OK:
		push_error("Could not save Android editor settings: " + error_string(error))
		quit(1)
		return
	print("Android export SDK/JDK paths configured.")
	quit(0)
