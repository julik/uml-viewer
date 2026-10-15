# Backlog after milestone 1

The reviews of milestone 1 found these items. None of them blocks the 5b gate or loses data. Fold each item into the plan of the milestone that touches its code, and remove it here when it is fixed.

## Visible to the user

  - A reload of the page shows raw JSON, because the reload drops the token. The fix needs a spec change (spec 7.1).
  - No command clears the queue.
  - The last failed command stays on the page, also after `failed.json` is deleted.
  - An invalid `edge_kinds` value gives no message. `title` and `crap_cutoffs` are not validated either.
  - A network failure inside the page refresh shows "could not draw the graph: Failed to fetch". Show a network message instead.
  - The context menu can open past the screen edge. The hover target of an arrow is 1.2 px wide.
  - A box whose level is null is drawn in the bottom partition, as if it were level 0.
  - `watch` prints "1 commands waiting". A corrupt `to-agent.json` stops `watch` with a backtrace.
  - `install-skill` gives no warning when the executable is a version-manager shim or a binstub. With rbenv, the bare `uml-viewer` command fails in a folder with a different Ruby version.
  - An executable path with a space or a ")" breaks the allowed-tools rules and the backticks in the skill.
  - Smoke prints only the count of violating edges. Spec 10 says it prints the edges.

## Scanner and policy

  - A reopened class keeps the parse errors of its first file only.
  - A `skip:` entry with a trailing slash never matches. Normalize it in the scanner or in PolicyFile.
  - `Foo::BAR = 1` is recorded as a reference, not as a secondary declaration.
  - `main_constant` and `own` are computed twice, in `build_classes` and in `build_edges`.
  - The graph keeps omitted namespaces. A child namespace whose classes are all omitted shows as an empty member.
  - In `policy.rb`, `kept` and `by_id` are the same map.
  - The resolver has a redundant `written_size < 2` guard and a redundant `.uniq`.
  - PolicyInit checks for the file and then writes it, so two starts at the same time can both write.

## Server, mailbox and CLI

  - The servlet depends on WEBrick ProcHandler internals (`@proc`, `get_instance`). webrick is pinned to `~> 1.9` for this reason.
  - `Commands` does not check the kind against the id: `folder:models` with kind `class` is accepted.
  - The policy poll thread is never joined. An error other than ENOENT ends it without a message.
  - A POST without Content-Length gets the HTML 411 page of WEBrick.
  - The rescanner worker still ends on `NoMemoryError` and `ScriptError`.
  - `done` with an unknown id still rewrites `to-agent.json` with the same content.
  - An unknown first word on the command line is read as a path.
  - Two starts at the same time both start a server.
  - The page has a dead `sessionStorage` fallback.
  - Some code blocks repeat. Clean them up when the code changes next.

## Tests

  - `workspace_test` leaves bare `Dir.mktmpdir` project folders. Use a helper that removes them.
  - The state-folder name test computes the name with the same formula as the code, so it cannot tell.
  - Untested in the resolver: the strip on a Rails-prefix candidate, three or more segments, a `::` prefix.
  - The PolicyFile line-number test does not pin the line.
  - Untested in the policy: the folder box type and label, arrows in both directions, an omitted kind box that keeps its namespaced classes, the `!omit` filter.
  - No test checks a busy port.
  - The stale-server test kills a child without a guard, so ESRCH can hide the real failure.
  - `agent_loop_test` opens stdin pipes that it does not use. A browser test calls `shutdown_server` twice.
  - No test ties the command forms in the skill to the CLI parser.
  - Smoke skips the git check when the scan raises. A path that is not a git repository passes without a message. An empty `expect.yml` gives an undefined-method error. The name regex is loose. No test covers a wrong kind or two projects.
  - Two tests failed once while the host slept: the policy-change rescan in `server_test`, and the Chrome start in `BrowserTest`. Both pass alone and on a second run. Check their time bounds.
