-- Compositor rules of the Waffle environment.

-- Focus by click, as on Windows 11, which this environment follows. The
-- pointer still reaches what it is over, scrolling included, but only a click
-- moves the keyboard. With focus following the pointer, the window a person
-- meant was lost on the way to the taskbar: crossing another window took focus
-- to it, so a click on the first window's button brought it up again instead
-- of minimising it.
hl.config({ input = { follow_mouse = 2 } })
