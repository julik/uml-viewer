# Backlog after milestone 2

The reviews of milestone 1 found these items. None of them blocks the 5b gate or loses data. Fold each item into the plan of the milestone that touches its code, and remove it here when it is fixed.

## Visible to the user

  - No command clears the queue.
  - The last failed command stays on the page, also after `failed.json` is deleted.
  - `crap_cutoffs` is not validated.
  - `watch` prints "1 commands waiting". A corrupt `to-agent.json` stops `watch` with a backtrace.
  - `install-skill` gives no warning when the executable is a version-manager shim or a binstub. With rbenv, the bare `uml-viewer` command fails in a folder with a different Ruby version.
  - An executable path with a space or a ")" breaks the allowed-tools rules and the backticks in the skill.

## Scanner and policy

  - PolicyInit checks for the file and then writes it, so two starts at the same time can both write.

## Server, mailbox and CLI

  - The servlet depends on WEBrick ProcHandler internals (`@proc`, `get_instance`). webrick is pinned to `~> 1.9` for this reason.
  - A POST without Content-Length gets the HTML 411 page of WEBrick.
  - The rescanner worker still ends on `NoMemoryError` and `ScriptError`.
  - `done` with an unknown id still rewrites `to-agent.json` with the same content.
  - An unknown first word on the command line is read as a path.
  - Two starts at the same time both start a server.
  - Some code blocks repeat. Clean them up when the code changes next.

## Tests

  - `workspace_test` leaves bare `Dir.mktmpdir` project folders. Use a helper that removes them.
  - The state-folder name test computes the name with the same formula as the code, so it cannot tell.
  - No test checks a busy port.
  - The stale-server test kills a child without a guard, so ESRCH can hide the real failure.
  - `agent_loop_test` opens stdin pipes that it does not use. A browser test calls `shutdown_server` twice.
  - No test ties the command forms in the skill to the CLI parser.
  - Two tests failed once while the host slept: the policy-change rescan in `server_test`, and the Chrome start in `BrowserTest`. Both pass alone and on a second run. Check their time bounds.
