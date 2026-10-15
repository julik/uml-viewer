# Milestone 1 exit gate (criterion 5b)

Fill this in by hand after a real session. Use the medium test app; do not name it here.

```
Field                                        Value
-----                                        -----
Date
Claude Code version
uml-viewer commit
Idle session woke on the Monitor event       yes / no
Time from right-click Omit to policy.yml     seconds
Permission prompts during the loop           count (must be 0)
Large app first screen readable              yes / no, with a note
```

Steps:

  1. `uml-viewer install-skill`
  2. `uml-viewer <medium app>` in one terminal.
  3. In Claude Code, ask: "watch the uml-viewer for <medium app>". Wait until the Monitor runs. Leave the session idle.
  4. In the browser, right-click a class and choose Omit. Note the time.
  5. Note the time when the class leaves the diagram, and count any permission prompts.
  6. Open the large app and look at the first screen.

Result: milestone 1 is done when the session woke and the prompt count is 0. When the session did not wake, stop and design the doorbell again before milestone 2.
