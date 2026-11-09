#Override ModLoader for GodotEngine
A ModLoader based on `override.cfg` without the need of decompiling Godot games.
It uses the exact same format from [godot-mod-loader](https://github.com/GodotModding/godot-mod-loader/tree/4.x-dev) but without hooks, class_names, or any features that needs decompiling or PCK injection. (Dependencies works.)
I still advice you to use [godot-mod-tool](https://github.com/GodotModding/godot-mod-tool/tree/4.x-dev) to fit the manifest.json and mod_main.gd.

#Installing mods
Just copy the files `override.cfg and` `override_mod_loader.gd` next to the `game.exe`, put mods in `override_mods` folder (to avoid conflicts with ModLoader.)
