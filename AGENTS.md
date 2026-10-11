# Ferry: agent guide

Ferry is a macOS menu bar app that routes clicked links to a browser and Chrome profile. The `ferry` CLI (built on [swiftcur](https://github.com/sunwrobert/swiftcur)) configures it. Every command returns structured output; add `--json` for JSON. Run `ferry --llms` for the full command list.

## Set up Ferry on a new Mac

1. Install and run first-time setup:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/sunwrobert/ferry/main/scripts/install.sh | bash
   ```

   If the user has an exported rules file, pass it: `… | bash -s -- --rules ~/path/ferry-rules.json`.

2. Tell the user to do the two things only they can do:
   - Click **Grant Access** in the window that opens on Chrome's folder. This lets Ferry read profile names.
   - Confirm the macOS dialog that makes Ferry the default browser. Links without a rule still open in their usual browser.

3. Verify with `ferry status`. Expect `systemBrowser: true` and a non-empty `chromeProfiles` list. If profiles are empty, run `ferry setup` again.

4. Add rules for what the user wants (next section), then report the rules table and a `ferry test` line for each site.

## Configure rules

1. `ferry browsers` lists browsers and Chrome profiles with names and emails. Map "work" and "personal" to these; usually the work profile has a company email. If it's ambiguous, ask. Never invent a profile name: an unknown name makes Chrome create an empty profile.
2. `ferry rules` shows existing rules. First match wins.
3. Add one rule per site, using the profile's email so rules survive moving to another Mac:

   ```bash
   ferry add --host youtube.com --browser chrome --profile me@gmail.com
   ferry add --host youtu.be --browser chrome --profile me@gmail.com
   ferry add --host github.com --browser chrome --profile me@company.com
   ferry add --regex '^https?://([^/]*\.)?company\.' --browser chrome --profile me@company.com
   ferry add --from-app slack --browser chrome --profile me@company.com
   ```

4. Check each one: `ferry test https://youtube.com/watch?v=x`.

`--host` covers subdomains (`www.`, `m.`). Short links on other domains, like `youtu.be`, need their own rule. Use `ferry set <n>`, `ferry move <n> <m>`, and `ferry remove <n>` to change rules, and `ferry default chrome --profile <email>` for links no rule matches.

## Move rules between Macs

```bash
ferry export --json > ferry-rules.json     # old Mac
ferry import ferry-rules.json              # new Mac (--merge to keep existing rules)
```

Exports store profiles as emails, so they work even when Chrome's folder names differ. `import` reports any profiles the new Mac doesn't have yet. The file contains the user's email addresses; keep it somewhere private, not in this public repo.

## Errors

Every error has a `code` and usually a suggested command. Common ones: `PROFILES_UNREADABLE` (run `ferry setup`), `PROFILE_NOT_FOUND` and `BROWSER_NOT_FOUND` (run `ferry browsers`), `APP_NOT_RESPONDING` (open Ferry.app and retry).

## Working on the code

`scripts/build.sh --install` builds `Ferry.app`, installs it to `~/Applications`, and links the CLI to `~/.local/bin/ferry`. The CLI and the app are one binary: `main.swift` runs the CLI when there are arguments.
