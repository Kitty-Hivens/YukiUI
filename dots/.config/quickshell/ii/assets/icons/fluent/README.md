The numbered directories -- `12`, `16`, `20`, `24`, `28`, `32`, `48` -- hold Microsoft's own open icon set, taken unchanged:

[microsoft/fluentui-system-icons](https://github.com/microsoft/fluentui-system-icons) -- `assets/<Name>/SVG/ic_fluent_<name>_<size>_<regular|filled>.svg`

License: [MIT](LICENSE-fluentui-system-icons), a copy of which sits beside this file. That set is not the same thing as the Segoe Fluent Icons font, which ships with Windows and is licensed only for apps that run on it.

Fluent publishes a separate drawing for every size, and they are not the same picture at different scales: the small ones carry a heavier stroke and drop detail the large ones keep. `FluentIcon` therefore picks the directory matching the size it is about to draw at, rather than scaling one file to everything. Where Microsoft does not publish a given size for a given icon, the nearest one it does publish was copied into that directory, so every directory holds the whole set and the lookup never has to fall back at runtime.

Twenty five names have no equivalent in that set and keep their earlier drawing in every directory: the taskbar's own `start-here`, `task-view` and `system-search` marks, the light and dark variants of those, `battery-full`, `ethernet`, `flash-on`, `speaker`, `mic-on`, `auto`, `widgets`, `empty`, and the `cloudflare` and `corporation` brand marks.

The flat `*.svg` files at the top level are that earlier set, kept because three places still read from here by name rather than by size -- the app icon widget's light and dark taskbar marks, the polkit dialog's shield, and the notification centre's generic application icon.

Of those, "start-here", "search" and "task view" are from:

[Windows 11 by Joshua Oghenekaro Okwe - Figma](https://www.figma.com/community/file/1123040825921884189/windows-11)

License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.en)

The rest of the flat set has no stated origin and is not the MIT set -- `add.svg` and Microsoft's `ic_fluent_add_24_regular.svg` are different drawings. Nothing reads those any more except the three cases above.
