---
title: PlayStation and Xbox controllers in games
tags: controller, gamepad, dualsense, dualshock, ps5, ps4, xbox, buttons wrong, scrambled buttons, controller not working
---
## Symptoms
A controller has missing or scrambled buttons in a game, or a game shows Xbox button icons for a PlayStation controller.

## Why
Most Windows games only understand Xbox controllers. Wine normally passes PlayStation controllers through as raw devices meant for games with their own PlayStation support, so other games get the buttons wrong.

## Fix in Ferry
- Ferry makes a DualSense or DualShock 4 show up as an Xbox controller in every game, on every engine. Games with their own PlayStation support still play normally, but show Xbox button icons.
- Ferry's Controller window (the controller button on the home page) draws the connected controller live, lets you rebind buttons, and has a Keyboard & Mouse mode for games that only take a keyboard and mouse. Save setups as named keybinds and load one before playing.

## What Ferry can't fix
Rebinding only works for games that read the controller as an Xbox controller (most do). The Controller window's changes aren't used for games with anti-cheat.
