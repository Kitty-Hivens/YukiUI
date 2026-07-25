<div align="center">
    <h1>YukiUI</h1>
    <h3>A Hyprland desktop shell, built on Quickshell</h3>
    <h4>Fork of <a href="https://github.com/end-4/dots-hyprland">Illogical Impulse</a></h4>
</div>

<div align="center">

![](https://img.shields.io/github/last-commit/Kitty-Hivens/YukiUI?&style=for-the-badge&color=8ad7eb&logo=git&logoColor=D9E0EE&labelColor=1E202B)
![](https://img.shields.io/github/stars/Kitty-Hivens/YukiUI?style=for-the-badge&logo=andela&color=86dbd7&logoColor=D9E0EE&labelColor=1E202B)
![](https://img.shields.io/github/repo-size/Kitty-Hivens/YukiUI?color=86dbce&label=SIZE&logo=protondrive&style=for-the-badge&logoColor=D9E0EE&labelColor=1E202B)

</div>

<div align="center">
    <h2>• overview •</h2>
    <h3></h3>
</div>

<details>
  <summary>What this is/isn't</summary>

  - Technically, configuration files
  - Realistically, mostly the custom graphical shell
  - NOT a system setup script: no graphic drivers, no zram setup, etc.

</details>

<details>
  <summary>Notable features</summary>

  - **Overview**: Shows open apps with live previews
  - **AI**: Gemini, Ollama, and more
  - **QoL**: screen translation, anti-flashbang, Google Lens
  - **Material themes**: Choose your wallpaper, done, enjoy
  - **Transparent installation**: Every command is shown before it's run

</details>

## Installation

Supported distros are Arch-based and NixOS. Anything else is on you.

```sh
git clone https://github.com/Kitty-Hivens/YukiUI.git
cd YukiUI
./setup install
```

Every command is printed before it runs, and you can skip individual ones. Conflicting files are backed up unless you pass `--skip-backup`.

The session runs under uwsm: `hyprland/execs.lua` calls `uwsm finalize` and starts the shell as a `uwsm app` unit. Pick the uwsm session in your display manager, or launch it that way from a tty -- a plain Hyprland session comes up without the shell.

Useful flags:

| Flag | Effect |
| ---- | ------ |
| `--core` | Shell and compositor only, no fish/fontconfig/misc configs |
| `-s`, `--skip-sysupdate` | Don't run the system package upgrade |
| `--via-nix` | Pull dependencies through Nix and home-manager (work in progress) |
| `--fontset <set>` | Pick a predefined font set, see `dots-extra/fontsets` |

`./setup --help` lists every subcommand and flag. To remove it again, `./setup uninstall`.

Dependencies are listed in [deps-info.md](https://github.com/Kitty-Hivens/YukiUI/blob/main/sdata/deps-info.md).

## Configuration

Settings live in two apps, both reachable from the right sidebar (`Super`+`N`):

- **Appearance** — everything about the shell itself: bar, background, interface, services
- **System** — distro info and links

The underlying config file is `~/.config/illogical-impulse/config.json`; the Appearance app opens it directly through the button in its navigation rail. Hyprland is configured in Lua under `~/.config/hypr/hyprland/`.

Keybinds should feel familiar if you've used Windows or GNOME. The important ones:

- `Super`+`/` — full keybind list
- `Super`+`Enter` — terminal
- `Super`+`N` — right sidebar

## Software overview

| Software | Purpose |
| ------------- | ------------- |
| [Hyprland](https://github.com/hyprwm/hyprland) | The compositor (manages and renders windows) |
| [Quickshell](https://quickshell.outfoxxed.me/) | A QtQuick-based widget system, used for the status bar, sidebars, etc. |
| Others | See [deps-info.md](https://github.com/Kitty-Hivens/YukiUI/blob/main/sdata/deps-info.md) |

<div align="center">
    <h2>• screenshots •</h2>
    <h3></h3>
</div>

[Showcase video](https://www.youtube.com/watch?v=RPwovTInagE)

| AI, settings app | Some widgets |
|:---|:---------------|
| <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/5d4e7d07-d0b4-4406-a4c9-ed7ba90e3fe4" /> | <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/6a32395f-9437-4192-8faf-2951a9e84cbe" /> |
| Window management | wow look its orange |
| <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/c51bed8b-3670-4d4c-9074-873be224fb8e" /> | <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/98703a66-0743-439f-a721-cef7afa6ab95" /> |

<div align="center">
    <h2>• thank you •</h2>
    <h3></h3>
</div>

 - [@end-4](https://github.com/end-4) for the original dotfiles this is forked from
 - [@clsty](https://github.com/clsty) for making the dotfiles accessible by taking care of the install script and many other things
 - [@midn8hustlr](https://github.com/midn8hustlr) for greatly improving the color generation system
 - [@outfoxxed](https://github.com/outfoxxed/) for being extremely supportive in the Quickshell journey
 - Quickshell: [Soramane](https://github.com/caelestia-dots/shell/), [FridayFaerie](https://github.com/FridayFaerie/quickshell), [nydragon](https://github.com/nydragon/nysh)
 - AGS: [Aylur](https://github.com/Aylur/dotfiles/tree/ags-pre-ts), [kotontrion](https://github.com/kotontrion/dotfiles)
 - EWW: [fufexan](https://github.com/fufexan/dotfiles)

<div align="center">
    <h2>• inspirations/copying •</h2>
    <h3></h3>
</div>

 - Inspiration: osu!lazer (Hybrid), Windows 11 (Windoes), AvdanOS (NovelKnock), Material Design 3 (m3ww & later)
 - Copying: Absolutely, feel free. Just follow the license and it's all good
