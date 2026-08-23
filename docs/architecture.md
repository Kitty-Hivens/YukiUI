# How the shell is put together

This describes the Quickshell config in `dots/.config/quickshell/yuki`. It is
written for someone about to add an environment or a plugin, and it spends most
of its length on the constraints that are not visible from the code.

## Two kinds of part

A **module** is a part of the shell. An **environment** is the module kind that
owns a whole desktop: its panels, the compositor rules it wants, its keys and
its look, taken together. Exactly one environment is built, because the others
are alternatives to it rather than companions.

A **plugin** extends whatever is already there. Every plugin that is enabled is
built, because each one adds something.

The distinction is not decoration. It decides how many are alive, what happens
when one is missing, and where its state belongs.

## The layers

    core/       the base: config, services, functions, models, panel loader
    common/     what both looks draw with: the appearance singleton and widgets
    ii/         the Illogical Impulse environment
    waffle/     the Waffle environment
    environments/   one directory per environment: manifest plus entry
    plugins/        one directory per plugin: manifest plus entry

Non-QML trees -- `assets/`, `scripts/`, `translations/`, `defaults/` -- sit at
the shell root and are reached through `Quickshell.shellPath(...)`, never by a
spelled-out path.

`core` may not name a surface belonging to an environment. Where shared code
needs a panel to react, it raises something neutral and the environment that has
that panel answers: `GlobalStates.panelDismissRequested()` is the example, and
`Notifications.viewerOpen` is the same idea from the other direction.

Panel state follows the same rule. `ii/IiStates.qml` and `waffle/WStates.qml`
each hold the flags of the panels their environment draws, under the names that
desktop actually uses. `GlobalStates` keeps only what belongs to no panel: the
lock, the screen sharing handshake, the Super key, the on-screen keyboard.

## What the scanner does, and what follows from it

Quickshell resolves `qs.*` module names by walking the **static import graph**
from the entry file and synthesizing a `qmldir` for every directory it visits.
Three consequences run through everything below.

**The shell root is the entry file's directory.** There is no way to import
upward past it. This is why `welcome.qml`, `appearanceSettings.qml`,
`systemSettings.qml` and `killDialog.qml` sit at the root: each is launched as
its own entry with `qs -p`, and a file one level down could not reach `core/`.

**A directory nobody imports has no qmldir**, so its types are "not installed"
however they are loaded later. `shell.qml` therefore imports each environment
directory for no reason except to register it:

    import "environments/ii"
    import "environments/waffle"

An import builds nothing. Which environment comes up, and whether one comes up
at all, is decided at runtime from the manifests. A directory that is not on
disk costs a warning from the scanner and is then simply absent.

**A missing directory is tolerated; a missing type is not.** That is what makes
runtime mounting possible at all.

## Environments

    environments/<dir>/manifest.json
    {
        "id": "ii",
        "name": "Illogical Impulse",
        "apiVersion": 1,
        "entry": "IiEnvironment.qml"
    }

The entry is a `Scope` holding one `PanelLoader` per panel. `Environments`
enumerates the manifests, builds exactly one entry, and destroys it when the
choice changes. The swap takes two beats with nothing alive in between, so that
an `IpcHandler` raised by the new environment is not refused a target the old
one still holds.

Failure modes are separated on purpose:

- *not installed* -- the name resolves to the fallback, and the config keeps
  what it said, so putting the environment back brings it back;
- *turned off* -- it stays out of the switcher but still answers to its own
  name, so turning it off does not evict someone already using it;
- *installed but will not build* -- recorded, set aside, and the fallback
  reaches past it. A broken environment costs its panels, not the desktop.

Adding one means: a directory under `environments/`, a manifest, an entry, the
panels themselves under a directory of their own, and **an import line in
`shell.qml`**. Without that line the scanner never reaches the new panels and
none of their types exist. A third-party environment dropped in without touching
`shell.qml` only works if it ships a hand-written `qmldir` in each of its
directories.

## Plugins

    plugins/<dir>/manifest.json
    {
        "id": "cloudflareWarp",
        "name": "Cloudflare WARP",
        "apiVersion": 1,
        "entry": "Plugin.qml",
        "config": { "autoRegister": false }
    }

The manifest is inert JSON, so a plugin is enumerated without any of its code
running. `apiVersion` must match the host exactly: a plugin written against
another generation is refused here rather than left to fail somewhere inside
itself, where the failure is much harder to read.

A plugin is reached by id, never by type name -- a type name has to exist when
the shell is parsed, and the whole point is that it might not:

    Plugins.get("cloudflareWarp")?.available ?? false

Two ids from two directories: the second is refused. It used to replace the
first in the registry while the first stayed alive with its processes and its
shortcuts, unreachable.

### What a plugin's entry may rely on

The entry is loaded by file URL, outside the `qs:` interception the rest of the
shell goes through. That gives it a shape worth knowing:

- **`qs.*` singletons are the same instances the shell uses.** There is no
  second copy.
- **A plain sibling type resolves.** Qt finds `Helper.qml` next to the entry by
  looking at the directory.
- **A sibling `pragma Singleton` does not.** A composite singleton needs a
  `qmldir` entry, and the scanner synthesizes none for a directory it never
  visited. Ship a hand-written `qmldir` in the plugin directory; that works, and
  it is the only thing that does.
- **`qs.*` imports only resolve for directories the shell's own import graph
  already reached.** A plugin importing something no shipped code imports gets
  "module is not installed".
- **`//@` pragmas in the entry have no effect**, for the same reason: they are
  handled by the interception the entry bypasses.
- **The entry must declare `property var settings`**, even with no `config`
  block, because the host passes it at construction either way.

A hyphen in the directory name is harmless: the id comes from the manifest and
the entry is loaded by URL.

### Settings

`config` in the manifest is a defaults document. The host generates a
`JsonAdapter` from it, so a plugin describes its settings as data and still gets
typed properties with change signals.

They live in `~/.config/illogical-impulse/plugins/<id>.json`, not in the shell's
own config. That file's adapter serializes by walking the properties it declares
and building a fresh object, so a key it does not know about is erased by the
next write of any setting at all -- and a plugin the shell has never heard of
cannot declare anything there.

Key names become QML property names, so they must start with a lower-case letter
and hold only letters, digits and underscores. An unusable name is reported and
skipped on its own; the rest of the settings survive.

An object in the schema becomes a nested `JsonObject` rather than a `var`,
because a `var` changed in place raises no signal and the change is then never
saved. An array is still a `var`, and has that trap: replace it, do not mutate
it.

Values arrive asynchronously. Bindings to `settings` are correct from the first
line; an imperative read in `Component.onCompleted` sees the defaults.

## Turning things on and off

Two deny lists in the config, `disabledEnvironments` and `disabledPlugins`.
Off and absent stay different answers: a disabled plugin is never built, so its
code cannot run, and a disabled environment stays installed and reachable by
name.

From a terminal:

    yukictl plugins list
    yukictl plugins disable <id>
    yukictl env use <id>

The command lives at `scripts/yukictl` inside the config and is linked into
`~/.local/bin` on install, so it follows whichever config directory it was
installed from rather than naming one.

Completing a word asks the shell for the ids, the same way the commands do, so
what is offered is what can be acted on. The files are in `scripts/completions`
-- one for bash, fish and zsh -- and are linked into place on install. zsh reads
only the directories it is given, so the installer prints the line to add.

`list` also prints why a directory was turned away -- a broken manifest, a
mismatched `apiVersion`, a duplicate id -- which is otherwise only a line in the
journal.
