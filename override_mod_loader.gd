extends Node

const MOD_LOADER_LOG := "totobono4_mod_loader:Log: "
const MOD_LOADER_WARN := "totobono4_mod_loader:Warning: "
const MOD_LOADER_ERR := "totobono4_mod_loader:Error: "

const MODS_PATH := "override_mods"
const UNPACKED_MODS_PATH := "res://mods-unpacked"

class ModData:
    var packed_path: String
    var unpacked_path: String
    var name: String
    var manifest_path: String
    var main_path: String

const MOD_MANIFEST_PATH := "manifest.json"
const MOD_MAIN_PATH := "mod_main.gd"

const MANIFEST_DEPENDENCIES_KEY := "dependencies"

var loaded_mods: Array[ModData]
var pending_mods: Array[ModData]
var ready_mods: Array[ModData]

var dream_translator_api_packed = "res://mods/totobono4-dream_translator_api.zip"
var french_dream_packed = "res://mods/totobono4-french_dream.zip"

var dream_translator_api_main_path := "res://mods-unpacked/totobono4-dream_translator_api/mod_main.gd"
var french_dream_main_path := "res://mods-unpacked/totobono4-french_dream/mod_main.gd"

var dream_translator_api_name = "totobono4-dream_translator_api"
var french_dream_name = "totobono4-french_dream"

var dream_translator_api: Node
var french_dream: Node

func _init() -> void:
    var game_path := OS.get_executable_path()
    var game_dir := game_path.get_base_dir()
    var mods_dir := game_dir.path_join(MODS_PATH)
    var game_dir_access := DirAccess.open(game_dir)

    if not game_dir_access.dir_exists(mods_dir):
        game_dir_access.make_dir(mods_dir)
        print(MOD_LOADER_LOG, "t_mods folder created, please add mods in t_mods folder.")
        return
    
    var mods_dir_access = game_dir_access.open(mods_dir)
    var mods = mods_dir_access.get_files()



    for mod in mods:
        var mod_data := ModData.new()
        mod_data.packed_path = mods_dir.path_join(mod)
        mod_data.unpacked_path = UNPACKED_MODS_PATH.path_join(mod.get_basename())
        mod_data.name = mod.get_basename()
        mod_data.manifest_path = mod_data.unpacked_path.path_join(MOD_MANIFEST_PATH)
        mod_data.main_path = mod_data.unpacked_path.path_join(MOD_MAIN_PATH)

        var loaded = ProjectSettings.load_resource_pack(mod_data.packed_path)

        if not loaded:
            print(MOD_LOADER_WARN, "Failed to load mod ", mod_data.name)
            continue
        print(MOD_LOADER_LOG, "Mod ", mod_data.name, " loaded.")

        loaded_mods.push_back(mod_data)
        pending_mods.push_back(mod_data)

    while not pending_mods.is_empty():
        var mod_data = pending_mods.pop_front()
        var manifest_path = mod_data.manifest_path

        if not FileAccess.file_exists(manifest_path):
            print(MOD_LOADER_WARN, mod_data.name, " don't have manifest, failed to init.")
            continue
        
        var manifest_file = FileAccess.open(manifest_path, FileAccess.READ)
        var content := manifest_file.get_as_text()

        var json_converter = JSON.new()
        var res = json_converter.parse(content)
        if not res == OK:
            print(MOD_LOADER_WARN, mod_data.name, " manifest is not json, failed to init.")
            continue

        if not json_converter.data is Dictionary:
            print(MOD_LOADER_WARN, mod_data.name, " manifest is not dictionary, failed to init.")
            continue

        var data = json_converter.data

        if not data.has(MANIFEST_DEPENDENCIES_KEY):
            print(MOD_LOADER_WARN, mod_data.name, " manifest don't have 'decepencies' key.")
        
        if data.has(MANIFEST_DEPENDENCIES_KEY):
            var loaded_mod_names = loaded_mods.map(func(e): return e.name)
            var launched_mod_names = ready_mods.map(func(e): return e.name)

            var missing_dependencies = false
            var pending_dependencies = false

            for dependency in data.get(MANIFEST_DEPENDENCIES_KEY):
                if not loaded_mod_names.has(dependency):
                    missing_dependencies = true
                    print(MOD_LOADER_WARN, mod_data.name, " can't load, missing dependency: ", dependency)
                    continue
                if not launched_mod_names.has(dependency):
                    pending_dependencies = true
                    continue

            if missing_dependencies:
                continue
            if pending_dependencies:
                pending_mods.push_back(mod_data)
                continue

        ready_mods.push_back(mod_data)
        print(MOD_LOADER_LOG, "Mod ", mod_data.name, " ready.")

    for mod in ready_mods:
        print(MOD_LOADER_LOG, "Launching mod ", mod.name, "..")

        var node = Node.new()
        node.set_name(mod.name)
        node.set_script(load(mod.main_path))
        add_child(node)
