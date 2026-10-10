# Ferry

A tiny native macOS menu bar app that sends each link to the right browser. A personal take on [Velja](https://sindresorhus.com/velja) and [Choosy](https://choosy.app/).

Pure Swift + AppKit, no dependencies, ~180 KB binary. No windows or web views. It routes the link and gets out of the way.

## Features

- Rules by host (subdomains included), URL regex, or the app the link was clicked in
- Chrome profiles: every profile appears in the picker and the Default Browser menu, and rules can target a profile by folder (`Profile 1`), name (`Work`), or email
- A picker menu at the cursor when no rule matches, or when you hold **⌥ Option** while clicking a link. Use number keys `1`–`9` to choose a browser.
- Copy Link from the picker
- Menu bar: choose the default browser; add, retarget, reorder, and delete rules; "Always Open <site> In…" from the picker; set Ferry as the system browser; launch at login

## Install

```bash
./scripts/build.sh --install
```

That builds `Ferry.app`, copies it to `~/Applications`, and launches it. Then open the menu bar icon, choose **Make Ferry the System Browser**, and confirm the macOS prompt.

## CLI

`./scripts/build.sh --install` also links the CLI to `~/.local/bin/ferry`.

```bash
ferry browsers                                            # browsers and Chrome profiles
ferry add --host youtube.com --browser chrome --profile Personal
ferry add --host devin.ai --browser chrome --profile you@work.com
ferry add --from-app slack --browser chrome --profile Work
ferry default chrome --profile Personal
ferry rules                                               # numbered; first match wins
ferry move 3 1
ferry remove 2
ferry test https://www.youtube.com/watch?v=x              # where would this go?
```

Every menu action has a CLI equivalent: `ferry set <n>` (change where a rule opens), `ferry status`, `ferry system-browser`, `ferry login on|off`, `ferry edit`, `ferry quit`. Run `ferry help` for everything. The CLI checks browser and profile names against what is installed, so a typo errors instead of silently creating a new Chrome profile.

## Agents

The CLI is built on [swiftcur](https://github.com/sunwrobert/swiftcur), so every command returns structured output (`--json`, `--format yaml`, …), and agents get:

```bash
ferry --llms        # compact command list for an agent's context
ferry skills add    # install the Ferry skill for Claude Code, Codex, Cursor, and other agents
ferry mcp add       # register Ferry as an MCP server
ferry --mcp         # run the MCP server over stdio
eval "$(ferry completions zsh)"
```

Misspelled flags are errors, and failures suggest the next command to run.

[`skills/ferry/SKILL.md`](skills/ferry/SKILL.md) teaches an agent to use the CLI. Link it into your skills folder:

```bash
ln -s "$PWD/skills/ferry" ~/.agents/skills/ferry
```

Then just say something like "open YouTube in my personal Chrome profile and Devin in my work one".

## Config

The config file is `~/.config/ferry/config.json`. It is read on every link, so edits apply immediately.

```json
{
  "defaultBrowser": "com.google.Chrome",
  "defaultProfile": "Personal",
  "hiddenBrowsers": [],
  "rules": [
    { "host": "meet.google.com", "browser": "com.google.Chrome" },
    { "host": "github.com", "browser": "com.google.Chrome", "profile": "you@work.com" },
    { "fromApp": "com.tinyspeck.slackmacgap", "browser": "com.google.Chrome", "profile": "Work" },
    { "regex": "^https://.*\\.atlassian\\.net/", "browser": "com.google.Chrome" }
  ]
}
```

The first matching rule wins. Every field set on a rule must match. Set `defaultBrowser` to `null` to show the picker every time.

To find a browser's bundle ID, run `osascript -e 'id of app "Google Chrome"'`.
