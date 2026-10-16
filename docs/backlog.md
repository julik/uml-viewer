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

## Found in milestone 2

Visible to the user:

  - The spec text in 7.1 and the section 9 row still say "a scanned file" where the route now serves only files of classes in the graph.
  - Spec 4.2, 9 and 10 still describe the ActiveAdmin pseudo-class as a version 1 rule. Only section 11 says it is deferred.
  - Session save is a trailing 1-second debounce, not a throttle.
  - Zoom has no lower or upper bound, and the zoom value is saved as it is.
  - The crumbs show the new view before its layout is done.
  - A graph fetch that fails with an HTTP error shows "could not draw the graph: HTTP 500".
  - Escape goes up a view instead of closing an open context menu.
  - A slow source response can land after a second click and show two files in the source panel.
  - A file that ends with a newline shows a numbered empty last line in the source panel.
  - The hover popup is not clamped to the window and can stay visible after a redraw removes the hovered arrow.
  - The open class card is not refreshed after a rescan, so its ops and line numbers can be stale.
  - A Regen that fails with an HTTP error says only the status, with no next step.
  - graph.json is about 2.6 MB on the large app (ops are 1.4 MB of it). Measure again before milestone 3 adds coverage per op, and consider serving ops per class on demand.

Scanner and policy:

  - `a&.b ||= 1` counts 1 for cyclomatic complexity. Spec 4.3 says 2.
  - The short-circuit write check scans a list of 16 classes per node. A Set is cleaner.
  - Ops are not collected from a def under an `if`, `begin` or `rescue` at class level.
  - A receiver-less call with a def argument and no block (`memoize def a`) loses the op.
  - `private_class_method :b` does not hide a `def b` inside `class << self`.
  - The unreadable-file check joins the path twice, and a directory named `x.rb` is listed as unreadable.
  - `existing_folders` ignores policy `skip:` entries.
  - `has_many "tags"` with a string first argument gives no edge and no count.
  - A superclass written as `Struct.new(:a)` records a foreign inheritance edge to Struct.

Server and CLI:

  - Smoke aborts with a backtrace when the git binary is missing.
  - A malformed expect.yml gives a YAML message that does not name expect.yml.
  - `/source` answers "file gone" when graph.json is missing, and a read error other than ENOENT gives the WEBrick HTML 500 page.
  - A watch error in /version hides a scan error while it is set.
  - `/source` serves the whole file with no size cap, and follows a scanned symlink out of the project.

Tests:

  - No test for `rescue A, B` (one clause) or for ensure and else (no count).
  - No test for a read-permission failure in the scan, for `Foo::BAR = Data.define(...)`, or that the constant-path-write visitor matters.
  - No test for app/lib mapping to lib or for a policy-skipped folder in `folders`.
  - No test that inheritance beats dependency on one pair.
  - The graph summary test cannot tell `unresolved` from `polymorphic` (both 0).
  - The Psych line test pins a Psych message text that can change between versions.
  - No views test for two foreign edges to one name.
  - The non-git smoke test assumes the temp folder is not inside a git work tree.
  - Session tests check only the message for most bad bodies, not the 400, not that a refused PUT leaves session.json unchanged, and not that GET and PUT need the token.
  - No test pins the server start order (server.json last). The shutdown test's fixed sleep can only false-green on a slow machine.
  - No browser tests for zoom and scroll restore, zoom surviving a live reload, Ctrl+- and +, or a double-click on a folder box. The no-token page test cannot tell the token guard from the 403 path.
  - No test that Escape closes the source panel before the card. The hover test does not check that a non-red pair is not red after a redraw.
