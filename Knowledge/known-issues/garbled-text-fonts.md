---
title: Garbled text, question marks or missing fonts
tags: garbled text, question marks, boxes, mojibake, japanese, chinese, korean, russian, fonts, language, text unreadable
---
## Symptoms
Text in a game shows as question marks, boxes or random symbols. Or a game made for Japan, China, Korea or Russia crashes or won't start.

## Why
Many games made for one language write text in that language's old character set, and only work when Windows is set to that language. Games also ask for Windows fonts by name, which a Mac doesn't have under those names.

## Fix in Ferry
- Windows language, in the game's Compatibility settings (or from Troubleshoot): set it to the language the game was made for. It only changes what that game sees, not the language the game itself uses; that's in its own settings, if it has one.
- Fonts are handled for you. In every environment, Ferry links common Windows fonts that macOS also has (such as Arial, Times New Roman, Verdana and Tahoma), and maps Japanese, Chinese and Korean Windows fonts (such as MS Gothic, SimSun and Malgun Gothic) to the Mac fonts that cover the same text.

## What Ferry can't fix
Ferry can't translate a game's text into another language. The Windows language setting only makes the game's own text show properly.
