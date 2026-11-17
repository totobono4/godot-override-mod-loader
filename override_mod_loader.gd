extends Node

const MOD_LOADER_LOG := "override_mod_loader:Log: "
const MOD_LOADER_WARN := "override_mod_loader:Warning: "
const MOD_LOADER_ERR := "override_mod_loader:Error: "

const MODS_PATH := "mods"

const MOD_LOADER_BEGIN := "ModLoader"
const PATCHED_PREFIX := "Patched_"

const CLASS_NAME_REGEX := "class_name (\\w+)"
const EXTENDS_REGEX := "(extends .*)"

const CONFIG_PATH := "user://override_mod_loader.cfg"
const SETTING := "setting"
const SETTING_PATCHED := "patched"
const SETTING_MOD_LOADER_CLASS_NAMES := "mod_loader_class_names"
const SETTING_PATCHED_ZIP := "patched_zip"

func CLASS_USE_REGEX(class_name_str) -> String :
	return "(?<!class_name )\\b" + class_name_str + "\\b"

func _init() -> void:
	var game_path := OS.get_executable_path()
	var game_dir := game_path.get_base_dir()
	var mods_dir := MODS_PATH

	var game_dir_access := DirAccess.open(game_dir)
	var mod_loader_path := ""
	var found_mod_loader := false

	for file in game_dir_access.get_files():
		if file.begins_with(MOD_LOADER_BEGIN) and file.get_extension() == "zip":
			mod_loader_path = file
			found_mod_loader = true
			break

	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)

	if err == OK and config.get_value("setting", "patched") and not game_dir_access.file_exists(config.get_value("setting", "patched_zip")):
		config.set_value("setting", "patched", false)
		config.save(CONFIG_PATH)

	var just_patched_mod_loader := false

	if err != OK or not config.get_value("setting", "patched"):
		if not found_mod_loader:
			print(MOD_LOADER_ERR, "ModLoader not found.")
			return

		just_patched_mod_loader = true
		config.set_value("setting", "patched", true)
		config.set_value("setting", "mod_loader_class_names", extract_classes(mod_loader_path))
		config.set_value("setting", "patched_zip", patch_zip(game_dir, mod_loader_path, config.get_value("setting", "mod_loader_class_names")))
		config.save(CONFIG_PATH)

	var class_name_strs = config.get_value("setting", "mod_loader_class_names")
	var patched_zip = config.get_value("setting", "patched_zip")

	if not ProjectSettings.load_resource_pack(patched_zip):
		print(MOD_LOADER_ERR, "Failed to load patched ModLoader.")
		return
	print(MOD_LOADER_LOG, "Patched ModLoader Loaded.")

	if just_patched_mod_loader:
		game_dir_access.remove(mod_loader_path)

	var mods_dir_access = game_dir_access.open(mods_dir)
	var mods = mods_dir_access.get_files()

	for mod in mods:
		if is_patched_zip(mod):
			continue
		var patched_mod = patch_zip(mods_dir, mods_dir.path_join(mod), class_name_strs)

		if not ProjectSettings.load_resource_pack(patched_mod):
			print(MOD_LOADER_WARN, "Failed to load mod ", mod.get_basename())
			continue
		print(MOD_LOADER_LOG, "Mod ", mod.get_basename(), " loaded.")

		mods_dir_access.remove(mod)

func extract_classes(zip_path : String) -> Dictionary[String, String]:
	var reader = ZIPReader.new()
	var reader_res = reader.open(zip_path)
	if reader_res != OK:
		print(MOD_LOADER_ERR, "Error reading " + zip_path)
		return reader_res

	return collect_class_name_strs(reader)


func patch_zip(root_dir : String, zip_path : String, class_name_strs : Dictionary[String, String]):
	var reader = ZIPReader.new()
	var reader_res = reader.open(zip_path)
	if reader_res != OK:
		print(MOD_LOADER_ERR, "Error reading " + zip_path)
		return reader_res

	var gdscript_const_dependencies = collect_const_dependencies(reader, class_name_strs)

	var patched_zip = get_patched_zip(zip_path)
	var patched_zip_path = root_dir.path_join(patched_zip)

	var writer = ZIPPacker.new()
	var writer_res = writer.open(patched_zip_path)
	if writer_res != OK:
		print(MOD_LOADER_ERR, "Error reading " + patched_zip_path)
		return writer_res

	print(MOD_LOADER_LOG, "Patching ", patched_zip_path, "..")

	var files = reader.get_files()

	for file_path in files:
		if file_path.ends_with("/"):
			writer.add_directory(file_path)
			continue

		var file = reader.read_file(file_path)

		if is_gdscript_valid(file_path):
			writer.start_file(file_path)
			var const_dependencies = ""
			if gdscript_const_dependencies.has(file_path):
				const_dependencies = gdscript_const_dependencies.get(file_path)
			var patched = patch_file(file, const_dependencies)
			writer.write_file(patched)
			writer.close_file()
		elif is_needed_file(file_path):
			writer.start_file(file_path)
			writer.write_file(file)
			writer.close_file()
	
	reader.close()
	writer.close()

	return patched_zip_path

func collect_class_name_strs(reader : ZIPReader):
	var files = reader.get_files()
	var class_name_strs : Dictionary[String, String]

	for file_path in files:
		if not is_gdscript_valid(file_path):
			continue

		var file = reader.read_file(file_path)

		if not has_class_name_str(file):
			continue

		class_name_strs.set(get_class_name_str(file), file_path)
	return class_name_strs

func collect_const_dependencies(reader: ZIPReader, class_name_strs : Dictionary[String, String]):
	var files = reader.get_files()
	var gdscript_const_dependencies : Dictionary[String, String]

	for file_path in files:
		if not is_gdscript_valid(file_path):
			continue

		var file = reader.read_file(file_path)
		var using_class_name_str = false
		var const_dependencies = ""

		for class_name_str_key in class_name_strs.keys():
			if not is_using_class_name_str(file, class_name_str_key):
				continue

			const_dependencies += "const " + class_name_str_key + " := preload(\"res://" + class_name_strs.get(class_name_str_key) + "\")\n"
			using_class_name_str = true

		if not using_class_name_str:
			continue

		gdscript_const_dependencies.set(file_path, const_dependencies)
	
	return gdscript_const_dependencies

func patch_file(file : PackedByteArray, const_dependencies : String) -> PackedByteArray:
	var unclassed_file = file
	if has_class_name_str(file):
		unclassed_file = remove_class_name_str(file)
	var patched = insert_after(unclassed_file, const_dependencies, EXTENDS_REGEX)
	return patched

func remove_class_name_str(file: PackedByteArray) -> PackedByteArray:
	return encode_utf8(reg_sub(decode_utf8(file), "", CLASS_NAME_REGEX))

func insert_after(file : PackedByteArray, insert : String, after_reg : String):
	if has_extends_str(file):
		var keep = get_extends_str(file) + "\n"
		return encode_utf8(reg_sub(decode_utf8(file), keep + insert, EXTENDS_REGEX))
	return encode_utf8(insert + decode_utf8(file))

func has_class_name_str(file : PackedByteArray) -> bool:
	var result = reg_search(decode_utf8(file), CLASS_NAME_REGEX)
	if result:
		return true
	return false

func get_class_name_str(file : PackedByteArray) -> String:
	var result = reg_search(decode_utf8(file), CLASS_NAME_REGEX)
	if result:
		return result.get_string(1)
	return ""

func is_using_class_name_str(file : PackedByteArray, class_name_str : String) -> bool:
	var result = reg_search(decode_utf8(file), CLASS_USE_REGEX(class_name_str))
	if result:
		return true
	return false

func has_extends_str(file : PackedByteArray) -> bool:
	var result = reg_search(decode_utf8(file), EXTENDS_REGEX)
	if result:
		return true
	return false

func get_extends_str(file : PackedByteArray) -> String:
	var result = reg_search(decode_utf8(file), EXTENDS_REGEX)
	if result:
		return result.get_string(1)
	return ""

func reg_search(search_str : String, reg_str : String) -> RegExMatch:
	var regex = RegEx.create_from_string(reg_str)
	return regex.search(search_str)

func reg_sub(subject_str : String, replacement_str : String, reg_str : String) -> String:
	var regex = RegEx.create_from_string(reg_str)
	return regex.sub(subject_str, replacement_str)

func is_gdscript_valid(file_path):
	var valid = true
	valid = valid and file_path.get_extension() == "gd"
	valid = valid and not file_path.contains("setup")
	return valid

func is_needed_file(file_path):
	var needed = false
	needed = true
	return needed

func decode_utf8(packed_byte_array : PackedByteArray) -> String:
	return packed_byte_array.get_string_from_utf8()

func encode_utf8(str : String) -> PackedByteArray:
	return str.to_utf8_buffer()

func get_patched_zip(zip_path) -> String:
	return PATCHED_PREFIX + zip_path.get_file()

func is_patched_zip(zip_path):
	return zip_path.begins_with(PATCHED_PREFIX)
