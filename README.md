# Overrun

A real-time strategy game for [Dazzle](https://github.com/dazzleos/dazzle):
build a base and command an army of robots (walkers, tanks and drones)
across a battlefield of hills and valleys. Everything is drawn in 3D, seen
from above at an isometric angle, and kept simple enough to run smoothly
on a Raspberry Pi Zero with many units on screen.

Install it on Dazzle from Settings, Software.

## Playing

- Drag a box to choose units, or click one (Shift: add to, or take from,
  what is chosen). Click the ground to send what is chosen there.
- Click the factory to queue units to make (right-click: take the last
  out); with it chosen, clicking the ground sets where they go once made.
- Arrow keys or W, A, S, D move the view; the wheel zooms. Esc: the menu.

## Building

Overrun is built with Dazzle's modules (kete_vc4 and the rest) and tools,
through Dazzle's `addApp` (see its `build.zig`): a commit of Dazzle's, as
`build.zig.zon` pins it. Zig is the version Dazzle's `scripts/zig` fetches:

    git clone https://github.com/dazzleos/dazzle ../dazzle
    ../dazzle/scripts/zig build test    # the tests, on this computer
    ../dazzle/scripts/zig build         # the program, and zig-out/apps

To try a build on a Pi, serve it with Dazzle's (Settings, Software,
Software server):

    cd ../dazzle && zig build serve -- --source=overrun=../overrun/zig-out
