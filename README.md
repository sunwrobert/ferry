# Ferry

A tiny native macOS menu bar app that sends each link to the right browser. A personal take on [Velja](https://sindresorhus.com/velja) and [Choosy](https://choosy.app/).

Pure Swift + AppKit, no dependencies, ~180 KB binary. No windows or web views. It routes the link and gets out of the way.

## Features

- Rules by host (subdomains included), URL regex, or the app the link was clicked in
- Chrome profiles: every profile appears in the picker and the Default Browser menu, and rules can target a profile by folder (`Profile 1`), name (`Work`), or email
- A picker menu at the cursor when no rule matches, or when you hold **⌥ Option** while clicking a link. Use number keys `1`–`9` to choose a browser.
- Copy Link from the picker
- Menu bar: choose the default browser, edit rules, set Ferry as the system browser, launch at login

## Install

```bash
./scripts/build.sh --install
```

That builds `Ferry.app`, copies it to `~/Applications`, and launches it. Then open the menu bar icon, choose **Make Ferry the System Browser**, and confirm the macOS prompt.

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
