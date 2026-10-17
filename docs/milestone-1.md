# Milestone 1 exit gate (criterion 5b)

Fill this in by hand after a real session. Use the medium test app; do not name it here.

```
Field                                                                                    Value
-----                                                                                    -----
Date                                                                                     2026-10-17
Claude Code version                                                                      2.1.302
uml-viewer commit                                                                        7f305ea (main, after milestone 4)
Permission mode (must be default)                                                        default (`claude --permission-mode default`)
uml-viewer rules already in ~/.claude/settings*.json or project settings (must be none)  none (checked all four files)
Idle session woke on the Monitor event                                                   yes (idle at 17:15, woke on "command 1 omit IsoWeek")
Time from right-click Omit to policy.yml                                                 29 s (click 17:16:17, Monitor event 17:16:18, policy.yml saved 17:16:46)
Permission prompts during the loop                                                       0
Prompt to load the skill (Skill tool call)                                               no ("Successfully loaded skill, 8 tools allowed")
Tool that prompted, if any                                                               none
Large app first screen readable                                                          yes: it opens and draws the first screen (user, 2026-10-17)
```

Steps:

  1. Check that no uml-viewer rule is in `~/.claude/settings.json`, `~/.claude/settings.local.json`, `.claude/settings.json` or `.claude/settings.local.json`. The skill must grant the rules on its own.
  2. `uml-viewer install-skill`
  3. `uml-viewer <medium app>` in one terminal.
  4. Start Claude Code in the default permission mode (no `--permission-mode`, no auto-accept). Ask: "watch the uml-viewer for <medium app>". Wait until the Monitor runs. Leave the session idle.
  5. In the browser, right-click a class and choose Omit. Note the time.
  6. In another terminal, run `stat -f %Sm "$(uml-viewer path <medium app>)/policy.yml"` to read the time the agent saved policy.yml.
  7. Note the time when the class leaves the diagram. Count any permission prompts, the one that loads the skill included, and write down the tool of each prompt.
  8. Open the large app and look at the first screen.

Result: milestone 1 is done when the session woke and the prompt count is 0. When the session did not wake, stop and design the doorbell again before milestone 2.

Result (2026-10-17): criterion 5b passes. The idle session woke on the Monitor event, and the loop (`inbox`, the `policy.yml` edit, `done`, `inbox`) ran with zero permission prompts. Loading the skill needed no prompt either. The session transcript confirms it: its only user messages are the start prompt and the Monitor notification, and it holds no permission request. The automated 5a test and `rake eval:skill` cover the same loop.
