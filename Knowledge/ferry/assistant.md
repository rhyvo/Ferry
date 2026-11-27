---
title: The built-in assistant
tags: assistant, ai, chat, apple intelligence, claude, chatgpt, gemini, api key, apply, undo, mcp, changes by the assistant, ask the assistant
---
Ferry has a built-in assistant you can ask in plain words why a game won't start or how to make it run better. It reads Ferry's own notes, so its answers match what Ferry can actually do.

Where it is: the assistant is a bar at the bottom of Ferry's window. Collapsed, it is one line: a sparkle, a game menu (it starts at No game), a box that says Ask the assistant about a game…, and a ⌃ button. Type there and press Return to send, and the chat opens. The ⌃ and ⌄ buttons open and collapse it, and the chat is kept when you collapse it. If an answer arrives while it is collapsed, a dot shows. When it is open, drag its top edge to make it taller or shorter. Right-click a game (or use its ⋯ menu) and choose Ask the Assistant…, or use Game ▸ Ask the Assistant…, or click Ask the assistant in Troubleshoot, and it opens with that game picked. New Chat starts over, and while the assistant is working a Stop button ends it. Answers show headings, lists and code properly, and each reply has Copy Reply.

Choosing a model: Settings ▸ AI ▸ Assistant.
- Apple: runs on your Mac, is free, and sends nothing anywhere. It needs macOS 26.4 or later with Apple Intelligence turned on. If it isn't available, the choice is greyed and says what it needs.
- Claude, ChatGPT or Gemini: you add your own API key. The key is kept in your Mac's Keychain, and the provider bills you for use. Ferry gets the list of models from the provider.
- Other: any OpenAI-compatible address, for example a model running on your own Mac.

What it can do depends on the model.
- Apple's model holds a real conversation: it remembers the chat, and its replies appear as they are written. It doesn't choose settings itself. For each message it only works out which Troubleshoot problem you describe, and Ferry then shows fix cards from Troubleshoot's own lists and the log check. A card can be Apply (with Undo afterwards), a menu for a setting with several values, Install then Turn On for a download, or a button that opens the log or a Mac setting. Nothing changes until you press a button. For example, a 32-bit game on Mach9 that crashes by running out of memory is offered Large address aware (4 GB).
- Claude, ChatGPT, Gemini and Other give deeper help: they read logs and settings themselves, change settings directly, edit config files, and start and test games. Each change shows as a card with Undo. The first time it needs a kind of action in a chat, Ferry asks your permission once for that kind. It always asks before downloads, deletes, changing save files, and anything outside the game's folder. Press Stop if you want it to stop.

Undoing later: every change the assistant makes is also listed in the game's settings under Changes by the assistant, each with Undo, even after the chat is closed.

MCP Servers (Settings ▸ AI): you can add extra tools for the assistant to use. They work with Claude, ChatGPT, Gemini and Other only, not Apple's model. Ferry asks once per server per chat before it uses one.

Privacy: personal paths and your Mac user name are hidden from what is sent to a cloud model. If you want nothing to leave your Mac, use Apple's model or a model running on your Mac.

Using Ferry from other AI apps: separately from the assistant, Settings ▸ AI ▸ Use Ferry from other AI apps lets Claude Code or Claude Desktop use Ferry's actions. Turn it on there and follow the setup shown.

If a request fails (offline, wrong key, too many requests), the chat says so in one sentence and you can just ask again. Check the key in Settings ▸ AI if it was refused.
