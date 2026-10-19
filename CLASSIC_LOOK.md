# The classic look

StarsGodot ships with its own simple pictures and its own wording. If you own a copy of **Stars! 2.6i**, the game can
take the original's pictures, and the wording of its turn messages, from **your own copy** and use them instead.
This is called the classic look.

The import happens on your computer, from files you already have. Nothing is downloaded, and nothing is sent
anywhere. The game plays exactly the same with or without the classic look: it only changes what you see.

## What you need

- An installed copy of Stars! 2.6i: the folder that holds `stars26i.exe`. Other versions (2.6j, 2.7 and so on) are
  refused for now, because their pictures may be laid out differently.
- If your copy is on a CD, a disk image or in a zip file, copy or extract it to a normal folder first.

## How to import it

1. Start StarsGodot. On the main menu, choose **Import Classic Look...**.
2. Pick the folder your copy of Stars! is installed in (the one with `stars26i.exe` in it), and confirm.
3. Wait a moment. The menu then tells you how many pictures and messages were imported, and that the classic look
   is on.

That's all. The import only reads your copy; it never changes it.

## What you get

- Ship and starbase pictures, in the planet and fleet tiles, the summary pane, the ship designer and the battle
  viewer.
- Planet pictures.
- Part pictures in the ship designer.
- Race logos, beside player names and on ships in the battle viewer.
- Pictures for minefields, mineral packets, salvage, wormholes and the Mystery Trader, on the map and when you
  select one.
- The title picture behind the main menu.
- The original wording of the turn messages. A message whose wording doesn't fit ours keeps ours.

Not imported: the original's help, sounds and music (the game has no sounds yet), and smaller interface pieces such
as toolbar buttons and cursors.

## Turning it off and on

The classic look is a mod called **Classic Look**. Open **Mods...** on the main menu and switch it off or on there.
Turning it off brings back the game's own pictures and wording; nothing is lost, and you can turn it on again later.

To import again (for example after reinstalling Stars!), run **Import Classic Look...** again: it replaces the
earlier import.

## Where it is kept

The imported files are kept in your StarsGodot user folder, in `mods/classic`:

- **Windows:** `%APPDATA%\Godot\app_userdata\StarsGodot\mods\classic`
- **Linux:** `~/.local/share/godot/app_userdata/StarsGodot/mods/classic`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/StarsGodot/mods/classic`

To remove it completely, delete that `classic` folder.

## Please don't share it

The pictures and wording in that folder belong to the makers of Stars!, and you are using them from your own
licensed copy. Please don't share the folder, upload it, or post screenshots of the game wearing the classic look.
Other players can make their own from their own copy.

## If something goes wrong

- **"stars26i.exe was not found in ..."**: the folder you picked isn't the one Stars! is installed in. Pick the
  folder that has `stars26i.exe` directly inside it.
- **"This copy is missing pictures ... is it Stars! 2.6i?"**: the file isn't Stars! 2.6i, or it is damaged. Only
  2.6i is supported for now.
- **"Picture ... could not be read."**: the file may be damaged. Try a fresh copy from your install media.
- **The mods could not be loaded**: open **Mods...**, switch the Classic Look off, then import again.

If none of this helps, please report it as an issue on the project's GitHub page. Say what the game printed, but
don't attach the imported files.
