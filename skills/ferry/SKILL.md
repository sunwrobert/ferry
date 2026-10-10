---
name: ferry
description: Configure Ferry, the user's macOS link router, which decides which browser and Chrome profile each link opens in. Use when the user asks to open certain sites or links in a specific browser or Chrome profile (e.g. "YouTube in my personal profile", "Devin links in my work profile", "Slack links in Chrome"), change the default browser or profile, or check where a link will open.
---

# Ferry

Ferry routes every clicked link to a browser and, for Chrome, a profile. Configure it only through the `ferry` CLI; it validates names against what is installed. Do not hand-edit `~/.config/ferry/config.json` unless the CLI cannot express the change.

## Workflow

1. Run `ferry browsers` to get the real browser names and Chrome profiles (display name, `[folder]`, email).
2. Map the user's words to a profile: "personal" or "work" usually match a profile's display name or its email domain. If nothing clearly matches, show the list and ask. Never invent a profile name.
3. Run `ferry rules` to see existing rules, so you don't add duplicates. First match wins.
4. Add rules with `ferry add`, one per site.
5. Verify every rule with `ferry test <url>` and report the output.

## Commands

```bash
ferry browsers                     # browsers + Chrome profiles
ferry rules                        # numbered rules
ferry config                       # default + rules
ferry add --host youtube.com --browser chrome --profile Personal
ferry add --host devin.ai --browser chrome --profile you@work.com
ferry add --regex '^https://docs\.google\.com/.*/d/' --browser chrome --profile Work
ferry add --from-app slack --browser chrome --profile Work   # links clicked in Slack
ferry add ... --at 1               # insert at a position instead of the end
ferry remove <n>
ferry move <n> <m>
ferry default chrome --profile Personal   # when no rule matches
ferry default --ask                       # show a picker when no rule matches
ferry test https://www.youtube.com/watch?v=x
ferry test https://example.com --from-app slack
```

## Matching

- `--host youtube.com` also matches subdomains (`www.youtube.com`, `m.youtube.com`). Short links on other domains need their own rule, e.g. `youtu.be`.
- Fields on one rule are ANDed. Put specific rules above broad ones with `--at` or `ferry move`.
- `--profile` accepts a display name, email, or folder (`Default`, `Profile 1`).

## Errors

- `can't read Google Chrome's profiles`: run `ferry setup`; it asks Ferry.app to show the macOS prompt. Tell the user to click Allow, then retry. Meanwhile folder names (`Default`, `Profile 1`) still work.
- `no browser matches`: the error lists what is installed; use one of those names.
- Rules only apply if Ferry is the system browser. If `ferry test` looks right but clicks don't route, ask the user to choose "Make Ferry the System Browser" in Ferry's menu.
