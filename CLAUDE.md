# uml-viewer instructions for Claude

## What this is

A Ruby gem that draws a UML class diagram of a Rails app in the browser and hands right-clicks to a Claude Code session. The spec is `docs/specs/2026-10-14-uml-viewer-design.md`. Each milestone in spec section 11 gets its own plan in `docs/plans/`. Known rough edges wait in `docs/backlog.md`.

## Milestone cycle

  1. Write the plan for the next milestone from the spec. Fold the matching `docs/backlog.md` items into it.
  2. Run an eng-review on the plan before any code.
  3. Execute task by task: strict TDD, a review per task, a whole-branch review at the end.
  4. Run `bundle exec rake smoke` on the real apps, then merge.

A milestone is done only when its exit gate passes. The gate of milestone 1 is criterion 5b, recorded in `docs/milestone-1.md`.

## Open source: no private names

- This repository is public. Never name a viewed app, its classes or its people in code, tests, docs or commit messages.
- Call the test apps "the medium app", "the large app" and "the legacy app". Use invented class names such as `Order` or `Reports::Summary` in examples.
- Smoke reads its paths from `UML_VIEWER_SMOKE`. The expected edges live outside the repository, in `~/.uml-viewer/projects/<project>/expect.yml`.

## Never write into a viewed project

- All state goes to `~/.uml-viewer/projects/<name>-<hash>/`. The viewer, the skill and smoke never create, change or commit a file in the viewed project.
- Smoke runs `git --no-optional-locks status` and asserts that the status did not change.

## Commands

```
Command                          Purpose
-------                          -------
bundle exec rake test            the full suite (unit, server, browser with Chrome)
bundle exec rake smoke           scan the real apps and check expect.yml
gem build uml-viewer.gemspec     build the gem to test the agent loop by hand
gem install --local <file.gem>   install it, then run uml-viewer install-skill
```

- Develop on Ruby 4.0.6 (`.ruby-version`). The gem supports Ruby 3.3 and later.
- With rbenv, the bare `uml-viewer` command works only in a folder with the Ruby version that holds the gem. Use the full path `~/.rbenv/versions/<version>/bin/uml-viewer` elsewhere. The installed skill already uses the full path.
- Do not edit `lib/uml/viewer/web/elk.bundled.js`. It is vendored elkjs 0.12.0, byte-identical to the release, under EPL-2.0.

## Code and tests

- Every change starts with a failing test. Watch it fail for the expected reason, then write the code.
- No comments above code. Names carry the intent.
- Every failure shows the user what went wrong and what to do next, and has a test that asserts the message.
- A test that waits on time has a bound. The host can sleep for minutes, so check `pmset -g log` before you call a slow run a regression.
- Commit messages follow Conventional Commits in English.
