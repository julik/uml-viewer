# uml-viewer milestone 2 (full scanner and navigation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the scanner (ops with cc, edge kinds, associations, ActiveAdmin), and let the user drill down from the first screen to a class card and its source lines, with rescans on every source change.

**Architecture:** The Scanner adds `ops`, edge `kinds` and foreign edges to its output. The pure Policy computes the violating flag from the kinds, and a new pure `Views` unit builds one view per open box (its child boxes, its classes and the collapsed arrows between them), so the page only draws. The server adds `/source` and `/session`, serves the page without a token, and polls every source file for changes.

**Tech Stack:** Ruby 4.0.6 for development (`.ruby-version`), gem floor Ruby 3.3; prism 1.9; webrick ~> 1.9; minitest 6; ferrum 0.18 (browser tests only); elkjs 0.12.0 vendored.

**Spec:** `docs/specs/2026-10-14-uml-viewer-design.md`. This plan covers milestone 2 of section 11. It folds in the matching items of `docs/backlog.md`.

**Milestone 1 gate.** Criterion 5b (the manual agent-loop check in `docs/milestone-1.md`) has not run yet. On 2026-10-15 the user chose to start milestone 2 before it. Milestone 2 does not touch `watch`, the mailbox or the skill. A doorbell redesign after 5b stays in those units. Task 1 records this in the spec.

## Global Constraints

- Gem name `uml-viewer`; `require "uml/viewer"`; code in `lib/uml/viewer/`; module `Uml::Viewer`.
- Runtime dependencies: `prism` (1.9 or later) and `webrick` (`~> 1.9`). No Rails, no ActiveSupport.
- `spec.required_ruby_version = ">= 3.3"`. Develop and test on Ruby 4.0.6.
- Never write a file into a viewed project. All state lives in `~/.uml-viewer/projects/<name>-<hash>/`, or under `UML_VIEWER_HOME` when it is set.
- State folder mode 0700; every state file mode 0600 (`Workspace#write_atomic` does this).
- No code or text copied from `unclebob/uml-viewer`.
- No private project names, class names or paths anywhere in the repository. Use the fixture names (`Order`, `Reports::Summary`, `Shop::Customer`, ...). Real edges go only into the private `expect.yml` files.
- Strict TDD: write the test, run it, see it fail for the expected reason, then write the code.
- No comments in code. English identifiers. No em dashes in any file.
- Every failure shows the user what went wrong and what to do next, and has a test that asserts the message.
- Commit messages: Conventional Commits, English, no session links or `Claude-Session` trailers.
- Every test sets `UML_VIEWER_HOME` to a temp folder (the test helper does this).
- Run commands with `export PATH="$HOME/.rbenv/shims:$PATH"` first; the Bash tool may lack the rbenv shims.
- Do not edit `lib/uml/viewer/web/elk.bundled.js`.

## Scope rulings for milestone 2

These are rulings, recorded here so a reviewer can reject them.

- **Drill-down data comes from Ruby.** A new pure unit `Views` builds one view per box: `graph["views"]` maps `"root"`, every namespace id and every `folder:<kind>` id to `{id, label, parent, nodes, arrows}`. The page only lays out and draws. `graph["boxes"]` and `graph["arrows"]` go away, and `graph["version"]` becomes 2. Reason: pure Ruby is cheap to test; JavaScript is testable only in the browser.
- **Where an edge shows.** Each class has a box path (for `Billing::Gateway::Client`: `Billing`, `Billing::Gateway`, the class). An edge shows once, in the view where the two paths split, as one arrow between the two child nodes there. An edge from `Reports::Summary` to `Order` shows on the first screen as `Reports -> folder:models`. Inside the `Reports` view it does not show, because `Order` is outside that box.
- **Foreign ovals** (spec 4.6) show on the first screen only, with arrows from the top-level boxes. They are never violating and have no right-click menu.
- **Ops.** Every `def` in a file belongs to the main class of that file, also a `def` inside another declared constant of the file (spec 4.2: the other constants resolve to the main class). A `def` inside another `def` is not an op. `def self.x`, a `def` inside `class << self` and a `def` inside a `class_methods do` block are named `self.x`. Each op has a `file`, because a reopened class merges ops from more than one file and the source panel needs the file.
- **Edge kinds.** Each edge has `kinds` (every kind found for the pair, strongest first) and `kind` (the first of them). The violating flag uses all kinds, so a merge never hides a red edge (spec 4.4). An `edge_kinds` override replaces all kinds of the pair.
- **One arrow style.** All kinds draw the same arrow. The hover popup lists the kind of each pair. Different UML arrowheads per kind can come later.
- **The page needs no token (spec change).** `GET /` serves `index.html`, which holds no data. The page reads the token from `?token=` or from `sessionStorage`. This fixes the backlog item "a reload of the page shows raw JSON". Every data route still needs `X-UML-Token`.
- **`GET /session` (spec gap).** The spec has `PUT /session` and says a restart restores the view, but gives no route to read it. `GET /session` returns `session.json`, or `{}`.
- **The class card shows `cc` only.** Coverage and CRAP come in milestone 3.
- **A box without a level** (its folder is in no row of `levels:`) is drawn in the partition above the highest level, out of the way. Milestone 1 drew it at the bottom as if it were level 0.
- **Singularize.** For `has_many` and `has_and_belongs_to_many`, the target is singularized also when it comes from `source:`. A singular `source:` that ends in `s` (`source: :address`) then loses its `s`. Accepted: rare, and the edge drops as unresolved, which the summary counts.
- **Source polling** stats every `*.rb` file under the source roots every 2 seconds, also files in skipped folders. A change there gives one harmless rescan.
- **Backlog items folded in:** reload shows raw JSON; an invalid `edge_kinds` value and a non-text `title` give no message; a network failure in the refresh says "Failed to fetch"; the context menu and the arrow hover target; a box with a null level; smoke prints only the count, skips the git check when the scan raises, passes a non-git path silently, crashes on an empty `expect.yml`, has a loose name regex and no wrong-kind or two-project test; reopened classes keep only the first file's parse errors; a `skip:` entry with a trailing slash; `Foo::BAR = 1`; `main_constant` computed twice; omitted namespaces kept in the graph; `kept` and `by_id`; the resolver guard and its untested cases; the PolicyFile line-number test; the policy test gaps; `Commands` does not check the kind against the id; the policy poll thread is never joined and dies silently; the dead `sessionStorage` fallback. Every other backlog item stays for a later milestone.

## Review Focus

1. `ActiveAdmin.register Shop::Customer`: the pseudo-class id holds `::`, so code that splits ids on `::` would put it in a `Shop` box and label it `Customer)`. Expected: it sits in the `admin` kind box with its full id as label, and `omit: [folder:admin]` removes it. Tests in Task 5 (Policy, browser) and Task 7 (Views).
2. A source file is deleted between the glob and the `stat` of the input poll (or is a dangling symlink). Expected: no exception, the poll thread keeps running, the next poll sees the change and rescans. Test in Task 9 (`Graph.inputs` with a dangling symlink).
3. `session.json` names a view that no longer exists (the namespace was omitted or renamed). Expected: the page opens the nearest view on the saved path that still exists, not a blank screen. Test in Task 10.
4. A reopened class across two files. Expected: the ops of both files, each with its own `file`, so the source panel opens the right file; the card lists both files; a parse error in the second file shows with that file's path. Test in Task 3.
5. `class_name: "::User"` inside a compact model whose namespace also has a `User`. Expected: the leading `::` forces the top-level `User`. Test in Task 4.

## Failure modes of the new paths

```
Failure                                  Handling                                  User sees                                         Test
-------                                  --------                                  ---------                                         ----
/source for a file outside the graph     403                                       source panel: "not a scanned file"                server_test, browser_test (Task 9, 11)
/source for a file deleted since scan    404                                       source panel: "file gone: <file>"                 server_test (Task 9)
PUT /session with a bad body             400 with the reason                       nothing (the page sends only valid bodies)        server_test (Task 9)
session.json names a missing view        nearest existing view on the path         that view                                         browser_test (Task 10)
graph.json fetch fails on the network    keep the last drawing                     banner: "server not reachable"                    browser_test (Task 10)
input poll cannot read the project       keep polling; error in /version           banner: "cannot watch the project: <reason>;      server_test (Task 9)
                                                                                   showing last good graph"
edge_kinds value or key is invalid       scan refuses, keeps the old graph         CLI error and banner with the edge_kinds rule     policy_file_test (Task 6)
title is not text                        scan refuses, keeps the old graph         "policy.yml: title must be text"                  policy_file_test (Task 6)
levels names an unknown folder           folder ignored                            scan: "warning: levels: unknown folder <name>"    cli_test (Task 8)
unresolved or polymorphic association    no edge, counted                          scan: "N unresolved associations, N polymorphic   cli_test (Task 8)
                                                                                   associations (no target)"
double-click on a class that left the    no card                                   toast: "class <id> is not in the graph"           browser_test (Task 11)
graph
Regen while the server is gone           no rescan                                 toast: "rescan not started: server not            browser_test (Task 11)
                                                                                   reachable"
smoke on a folder that is not git        project fails                             "<name>: not a git repository, so smoke cannot    smoke_test (Task 8)
                                                                                   check that git status stays the same"
expect.yml is not a list                 project fails                             "<name>: expect.yml must be a list of edges"      smoke_test (Task 8)
```

## File structure

```
Path                                         Change    Responsibility
----                                         ------    --------------
docs/specs/2026-10-14-uml-viewer-design.md   modify    record the rulings above (Task 1)
lib/uml/viewer/complexity.rb                 create    pure: cyclomatic complexity of one def (spec 4.3)
lib/uml/viewer/operations.rb                 create    ops of one parsed file: name, visibility, cc, lines
lib/uml/viewer/inflector.rb                  create    pure: singularize and camelize for association names
lib/uml/viewer/views.rb                      create    pure: one view per box, with nodes and collapsed arrows
lib/uml/viewer/scanner.rb                    modify    ops, edge kinds, associations, ActiveAdmin, foreign edges
lib/uml/viewer/resolver.rb                   modify    drop the redundant guard
lib/uml/viewer/policy.rb                     modify    kinds-aware violating, foreign edges, warnings, views
lib/uml/viewer/policy_file.rb                modify    validate edge_kinds and title
lib/uml/viewer/graph.rb                      modify    graph version 2, summary counts, ids by kind, inputs
lib/uml/viewer/commands.rb                   modify    check the target id against its kind
lib/uml/viewer/server.rb                     modify    page without token, /source, /session, input polling
lib/uml/viewer/cli.rb                        modify    scan prints the association counts and warnings
lib/uml/viewer/smoke.rb                      modify    print violating edges; git and expect.yml checks
lib/uml/viewer/web/index.html, app.js        modify    drill-down, crumbs, zoom, session, card, source, popup
lib/uml/viewer.rb                            modify    require the new units
test/fixtures/projects/rails_shapes/...      modify    Reports::Exporter (visibility), two ActiveAdmin files
test/*_test.rb                               modify    one test file per unit, plus new ones for new units
docs/backlog.md, README.md                   modify    remove the fixed items, describe navigation (Task 12)
```

---

### Task 1: Record the milestone 2 rulings in the spec

**Files:**
- Modify: `docs/specs/2026-10-14-uml-viewer-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the spec text that the reviewers of Tasks 2 to 12 check against.

This task changes documentation only, so it has no test. Make each edit with the exact text below.

- [ ] **Step 1: Units table (section 3.1).** After the `Policy` row block (the row that ends with `the root kind boxes and proposal views`), insert:

```
Views               one view per box: its child boxes, its classes      none (pure)
                    and the collapsed arrows between them
```

- [ ] **Step 2: ops row (section 4.2).** Replace the first two lines of the `ops` row:

```
ops            [{name, visibility, cc,         def nodes; `private`/`protected` with and
               line_start, line_end}]          without arguments; `def self.x` is public
```

with:

```
ops            [{name, visibility, cc, file,   def nodes; `private`/`protected` with and
               line_start, line_end}]          without arguments; `def self.x` is public
```

Then add this paragraph directly after the closing fence of that table:

```
Every `def` in a file belongs to the main class of that file. A `def` inside another `def` is not an op. `def self.x`, a `def` inside `class << self` and a `def` inside a `class_methods do` block get the name `self.x`. Each op names its file, because a reopened class merges the ops of more than one file.
```

- [ ] **Step 3: Routes table (section 7.1).** Replace the row `GET /                      index.html (needs ?token=)` with `GET /                      index.html (holds no data; no token)`. Replace the row `GET /source?file=&line=    the file text, only for files in the scanned set` with `GET /source?file=&line=    {file, line, text}, only for a file of a class in the graph`. Insert this row directly above the `PUT /session` row:

```
GET /session               the stored view, or {}
```

- [ ] **Step 4: Trust boundary (section 7.1).** Replace the sentence that starts with "`token` is 32 random hex characters" up to "so it stays out of the browser history)." with:

```
`token` is 32 random hex characters, new at each server start. Every route except the page and the two static scripts needs the header `X-UML-Token: <token>`. The page holds no data. It reads the token from its own URL once, keeps it in `sessionStorage` for a reload, and removes it from the address bar with `history.replaceState`, so it stays out of the browser history.
```

Keep the rest of that bullet (the CORS preflight and the 403) as it is.

- [ ] **Step 5: Page behavior (section 7.3).** After the bullet "Double-click a box: open the next level. Esc or the back label: up one level.", insert:

```
- A view shows the child boxes and the classes of the open box. An edge shows once, in the view where the box paths of its two ends split, as one arrow between the two child nodes there. Foreign ovals show on the first screen only.
- A box whose folder is in no row of `levels:` sits above the highest level.
```

- [ ] **Step 6: Delivery (section 11).** At the end of the milestone 1 bullet, add:

```
On 2026-10-15 the user chose to start milestone 2 before the 5b gate, because milestone 2 does not touch `watch`, the mailbox or the skill. 5b stays the exit gate of milestone 1, and a doorbell redesign stays in those units.
```

- [ ] **Step 7: Check and commit**

Run: `grep -c "$(printf '\xe2\x80\x94')" docs/specs/2026-10-14-uml-viewer-design.md` (counts em dashes)
Expected: `0`

```bash
git add docs/specs/2026-10-14-uml-viewer-design.md
git commit -m "docs(spec): record the milestone 2 rulings for views, ops, the page token and the session"
```

---

### Task 2: Complexity

**Files:**
- Create: `lib/uml/viewer/complexity.rb`
- Modify: `lib/uml/viewer.rb`
- Test: `test/complexity_test.rb`

**Interfaces:**
- Consumes: `prism`.
- Produces: `Uml::Viewer::Complexity.of(def_node) -> Integer`, where `def_node` is a `Prism::DefNode`.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

module Uml
  module Viewer
    class ComplexityTest < TestCase
      def cc(source)
        Complexity.of(Prism.parse(source).value.statements.body.first)
      end

      def test_the_spec_example_with_one_if_one_and_one_rescue_and_one_safe_call_has_cc_5
        assert_equal 5, cc(<<~RUBY)
          def check(order)
            return if order.nil?
            order.paid? && order.shipped?
            order&.total
          rescue ArgumentError
            0
          end
        RUBY
      end

      def test_a_method_without_branches_has_cc_1
        assert_equal 1, cc("def total = 0")
        assert_equal 1, cc("def empty; end")
      end

      def test_each_conditional_form_counts_one
        assert_equal 2, cc("def x\n  a if b\nend"), "modifier if"
        assert_equal 2, cc("def x\n  b ? 1 : 2\nend"), "ternary"
        assert_equal 2, cc("def x\n  unless b then a end\nend"), "unless"
        assert_equal 3, cc("def x\n  if a then 1 elsif b then 2 else 3 end\nend"), "if with elsif"
      end

      def test_each_loop_form_counts_one
        assert_equal 2, cc("def x\n  a while b\nend"), "while"
        assert_equal 2, cc("def x\n  a until b\nend"), "until"
        assert_equal 2, cc("def x\n  for i in list do a end\nend"), "for"
      end

      def test_each_when_and_each_in_counts_one
        assert_equal 3, cc("def x\n  case a\n  when 1 then :one\n  when 2 then :two\n  else :many\n  end\nend")
        assert_equal 3, cc("def x\n  case a\n  in Integer then 1\n  in String then 2\n  end\nend")
      end

      def test_each_rescue_clause_counts_one
        assert_equal 3, cc("def x\n  a\nrescue A\n  1\nrescue B\n  2\nend"), "two rescue clauses"
        assert_equal 2, cc("def x\n  a rescue nil\nend"), "rescue modifier"
      end

      def test_boolean_operators_and_short_circuit_writes_count_one_each
        assert_equal 3, cc("def x\n  a and b or c\nend"), "and, or"
        assert_equal 2, cc("def x\n  @a ||= 1\nend"), "instance variable ||="
        assert_equal 2, cc("def x\n  a &&= 1\nend"), "local &&="
        assert_equal 2, cc("def x\n  self.a ||= 1\nend"), "attribute ||="
      end

      def test_an_iterator_block_does_not_count_but_a_branch_inside_it_does
        assert_equal 1, cc("def x\n  list.each { |item| item }\nend")
        assert_equal 2, cc("def x\n  list.each { |item| item if item }\nend")
      end

      def test_a_nested_def_counts_for_the_method_that_holds_it
        assert_equal 2, cc("def x\n  def y\n    a if b\n  end\nend")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Itest -Ilib test/complexity_test.rb`
Expected: 9 errors, `NameError: uninitialized constant Uml::Viewer::Complexity`.

- [ ] **Step 3: Write minimal implementation**

`lib/uml/viewer/complexity.rb`:

```ruby
require "prism"

module Uml
  module Viewer
    module Complexity
      BRANCHES = [
        Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode, Prism::WhenNode,
        Prism::InNode, Prism::RescueNode, Prism::RescueModifierNode, Prism::AndNode, Prism::OrNode
      ].freeze
      SHORT_CIRCUIT_WRITES = Prism.constants.grep(/(And|Or)WriteNode\z/).map { |name| Prism.const_get(name) }.freeze

      def self.of(definition)
        1 + count(definition.body)
      end

      def self.count(node)
        return 0 if node.nil?

        (branch?(node) ? 1 : 0) + node.compact_child_nodes.sum { |child| count(child) }
      end

      def self.branch?(node)
        BRANCHES.include?(node.class) || SHORT_CIRCUIT_WRITES.include?(node.class) ||
          (node.respond_to?(:safe_navigation?) && node.safe_navigation?)
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/complexity"` directly after `require_relative "viewer/resolver"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Itest -Ilib test/complexity_test.rb`
Expected: `9 runs, 21 assertions, 0 failures, 0 errors`.

- [ ] **Step 5: Check that the tests can tell.** Remove `Prism::RescueNode` from `BRANCHES` and run again. Expected: the spec example and the rescue test fail. Restore the line.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/complexity.rb lib/uml/viewer.rb test/complexity_test.rb
git commit -m "feat: compute the cyclomatic complexity of a method from its Prism node"
```

---

### Task 3: Ops in the scan, and the scanner clean-ups

**Files:**
- Create: `lib/uml/viewer/operations.rb`
- Create: `test/fixtures/projects/rails_shapes/app/services/reports/exporter.rb`
- Modify: `lib/uml/viewer/scanner.rb`, `lib/uml/viewer.rb`
- Test: `test/operations_test.rb`, `test/scanner_test.rb`

**Interfaces:**
- Consumes: `Complexity.of(def_node)` (Task 2).
- Produces:
  - `Uml::Viewer::Operations.new(program, file).collect -> [op]`, where `program` is a `Prism::ProgramNode` and each op is `{"name" => String, "visibility" => "public"|"private"|"protected", "cc" => Integer, "file" => String, "line_start" => Integer, "line_end" => Integer}`.
  - Each scanned class gains `"ops" => [op]`. A reopened class has the ops of all its files, first file first.
  - A parse error of a later file of a reopened class reads `"<file> line N: <message>"`. The first file keeps `"line N: <message>"`.
  - `Foo::BAR = 1` (a `ConstantPathWriteNode`) is a secondary constant of its file. `Scanner.new(root, skip: ["app/x/"])` drops `app/x` (trailing slash ignored).

- [ ] **Step 1: Write the fixture file.** `test/fixtures/projects/rails_shapes/app/services/reports/exporter.rb`, exactly these 28 lines (line numbers matter):

```ruby
module Reports
  class Exporter
    def self.build = new
    private_class_method def self.secret = 1

    def run
      rows.map { |row| format(row) if row }
    end

    protected

    def rows = []

    private

    def format(row) = row.to_s
    def helper = nil
    public :helper

    class << self
      def defaults = {}

      private

      def hidden = nil
    end
  end
end
```

- [ ] **Step 2: Write the failing tests.** `test/operations_test.rb`:

```ruby
require "test_helper"

module Uml
  module Viewer
    class OperationsTest < TestCase
      def ops(source, file: "app/models/order.rb")
        Operations.new(Prism.parse(source).value, file).collect
      end

      def shape(source)
        ops(source).map { |op| [op["name"], op["visibility"]] }
      end

      def test_an_op_has_its_name_visibility_cc_file_and_lines
        assert_equal [{ "name" => "total", "visibility" => "public", "cc" => 2, "file" => "app/models/order.rb", "line_start" => 2, "line_end" => 4 }],
                     ops("class Order\n  def total\n    0 if empty?\n  end\nend\n")
      end

      def test_an_endless_def_starts_and_ends_on_one_line
        assert_equal [[3, 3]], ops("class Order\n\n  def total = 0\nend\n").map { |op| op.values_at("line_start", "line_end") }
      end

      def test_private_without_arguments_applies_to_the_defs_below_it
        assert_equal [["a", "public"], ["b", "private"], ["c", "protected"]],
                     shape("class X\n  def a; end\n  private\n  def b; end\n  protected\n  def c; end\nend\n")
      end

      def test_private_with_a_name_or_a_def_applies_to_that_method_only
        assert_equal [["a", "private"], ["b", "private"], ["c", "public"]],
                     shape("class X\n  def a; end\n  private :a\n  private def b; end\n  def c; end\nend\n")
      end

      def test_public_with_a_name_after_private_makes_that_method_public
        assert_equal [["a", "public"]], shape("class X\n  private\n  def a; end\n  public :a\nend\n")
      end

      def test_def_self_is_public_under_private_unless_private_class_method
        assert_equal [["self.a", "public"], ["self.b", "private"], ["self.c", "private"]],
                     shape("class X\n  private\n  def self.a; end\n  def self.b; end\n  private_class_method :b\n  private_class_method def self.c; end\nend\n")
      end

      def test_a_def_inside_class_self_is_a_singleton_op_with_its_own_visibility
        assert_equal [["self.a", "public"], ["self.b", "private"]],
                     shape("class X\n  class << self\n    def a; end\n    private\n    def b; end\n  end\nend\n")
      end

      def test_a_def_in_a_class_methods_block_is_a_singleton_op
        assert_equal [["self.find_all", "public"]],
                     shape("module Trackable\n  extend ActiveSupport::Concern\n  class_methods do\n    def find_all; end\n  end\nend\n")
      end

      def test_a_def_inside_a_def_is_not_an_op
        assert_equal [["outer", "public"]], shape("class X\n  def outer\n    def inner; end\n  end\nend\n")
      end

      def test_a_def_in_a_data_define_block_and_a_def_in_a_nested_class_are_ops_of_the_file
        assert_equal [["area", "public"], ["code", "public"]],
                     shape("module Shapes\n  Circle = Data.define(:r) do\n    def area = r * r\n  end\n\n  class Error < StandardError\n    def code = 1\n  end\nend\n")
      end

      def test_private_in_a_nested_class_does_not_leak_into_the_outer_class
        assert_equal [["inner", "private"], ["outer", "public"]],
                     shape("class X\n  class Y\n    private\n    def inner; end\n  end\n  def outer; end\nend\n")
      end
    end
  end
end
```

Add these tests to `test/scanner_test.rb` (inside the class, after the last test):

```ruby
      def test_each_class_lists_its_ops_with_lines
        assert_equal [["labels", 4, 4], ["price", 5, 5], ["parse", 6, 6], ["total", 7, 7]],
                     klass("Order")["ops"].map { |op| op.values_at("name", "line_start", "line_end") }
        assert_equal [["initialize", "public", 2, 4, 1]],
                     klass("Pricing")["ops"].map { |op| op.values_at("name", "visibility", "line_start", "line_end", "cc") }
      end

      def test_the_fixture_shows_every_visibility_form
        assert_equal [
          ["self.build", "public", 3, 1], ["self.secret", "private", 4, 1], ["run", "public", 6, 2],
          ["rows", "protected", 12, 1], ["format", "private", 16, 1], ["helper", "public", 17, 1],
          ["self.defaults", "public", 21, 1], ["self.hidden", "private", 25, 1]
        ], klass("Reports::Exporter")["ops"].map { |op| op.values_at("name", "visibility", "line_start", "cc") }
      end

      def test_a_reopened_class_merges_ops_and_parse_errors_of_both_files
        root = project(
          "app/models/order.rb" => "class Order\n  def total = 0\nend\n",
          "app/models/order_extra.rb" => "class Order\n  def tax = 1\n  def x(\nend\n"
        )
        order = Scanner.new(root).scan["classes"].find { |entry| entry["id"] == "Order" }
        assert_equal ["app/models/order.rb", "app/models/order_extra.rb"], order["files"]
        assert_equal [["total", "app/models/order.rb"], ["tax", "app/models/order_extra.rb"]],
                     order["ops"].first(2).map { |op| op.values_at("name", "file") }
        refute_empty order["parse_errors"]
        assert_match(%r{\Aapp/models/order_extra\.rb line \d+: }, order["parse_errors"].first)
      end

      def test_a_skip_entry_with_a_trailing_slash_drops_the_folder
        scan = Scanner.new(fixture, skip: ["app/controllers/"]).scan
        assert_nil scan["classes"].find { |entry| entry["id"] == "OrdersController" }
      end

      def test_a_constant_path_write_is_a_secondary_constant_of_its_file
        root = project(
          "app/services/billing/limits.rb" => "module Billing\n  class Limits\n  end\nend\nBilling::DEFAULT = 5\n",
          "app/services/invoice.rb" => "class Invoice\n  def cap = Billing::DEFAULT\nend\n"
        )
        result = Scanner.new(root).scan
        assert edge?("Invoice", "Billing::Limits", in_scan: result)
        refute_includes result["foreign"].map(&:first), "Billing"
      end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/operations_test.rb`
Expected: 11 errors, `NameError: uninitialized constant Uml::Viewer::Operations`.

Run: `bundle exec ruby -Itest -Ilib test/scanner_test.rb`
Expected: the ops tests fail with `undefined method 'map' for nil` (no `ops` key); the reopened-class test fails the same way; the trailing-slash test fails (`OrdersController` is still there); the constant-path test fails (no edge `Invoice -> Billing::Limits`).

- [ ] **Step 4: Write `lib/uml/viewer/operations.rb`**

```ruby
require "prism"

module Uml
  module Viewer
    class Operations
      VISIBILITIES = %i[public private protected].freeze

      def initialize(program, file)
        @program = program
        @file = file
        @ops = []
      end

      def collect
        scope(@program.statements.body, singleton: false)
        @ops
      end

      private

      def scope(statements, singleton:)
        state = { visibility: "public", named: {}, private_singletons: [], added: [] }
        statements.each { |node| visit(node, state, singleton) }
        state[:added].each { |op, receiver| settle(op, receiver, state) }
      end

      def visit(node, state, singleton)
        case node
        when Prism::DefNode then state[:added] << add(node, state[:visibility], singleton)
        when Prism::ClassNode, Prism::ModuleNode then scope(statements_of(node.body), singleton: false)
        when Prism::SingletonClassNode then scope(statements_of(node.body), singleton: true)
        when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode then scope_block(node.value, singleton: false)
        when Prism::CallNode then visit_call(node, state, singleton)
        end
      end

      def visit_call(node, state, singleton)
        arguments = node.arguments&.arguments
        if node.receiver.nil? && VISIBILITIES.include?(node.name)
          set_visibility(node.name.to_s, arguments, state, singleton)
        elsif node.receiver.nil? && node.name == :private_class_method
          arguments.to_a.each do |argument|
            state[:added] << add(argument, "public", singleton) if argument.is_a?(Prism::DefNode)
            name = argument.is_a?(Prism::DefNode) ? argument.name.to_s : literal(argument)
            state[:private_singletons] << name if name
          end
        else
          scope_block(node, singleton: node.name == :class_methods)
        end
      end

      def set_visibility(visibility, arguments, state, singleton)
        if arguments.nil?
          state[:visibility] = visibility
          return
        end

        arguments.each do |argument|
          if argument.is_a?(Prism::DefNode)
            state[:added] << add(argument, visibility, singleton)
          elsif (name = literal(argument))
            state[:named][name] = visibility
          end
        end
      end

      def settle(op, receiver, state)
        name = op["name"].delete_prefix("self.")
        if receiver
          op["visibility"] = "private" if state[:private_singletons].include?(name)
        elsif state[:named].key?(name)
          op["visibility"] = state[:named][name]
        end
      end

      def add(node, visibility, singleton)
        receiver = !node.receiver.nil?
        op = {
          "name" => receiver || singleton ? "self.#{node.name}" : node.name.to_s,
          "visibility" => receiver ? "public" : visibility,
          "cc" => Complexity.of(node),
          "file" => @file,
          "line_start" => node.location.start_line,
          "line_end" => node.location.end_line
        }
        @ops << op
        [op, receiver]
      end

      def scope_block(node, singleton:)
        return unless node.is_a?(Prism::CallNode) && node.block.is_a?(Prism::BlockNode)

        scope(statements_of(node.block.body), singleton: singleton)
      end

      def statements_of(body)
        body.is_a?(Prism::StatementsNode) ? body.body : []
      end

      def literal(node)
        node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/operations"` directly after `require_relative "viewer/complexity"`.

- [ ] **Step 5: Run the operations test**

Run: `bundle exec ruby -Itest -Ilib test/operations_test.rb`
Expected: `11 runs, 11 assertions, 0 failures`.

- [ ] **Step 6: Change the scanner.** In `lib/uml/viewer/scanner.rb`:

  1. In `initialize`, change `@skip = SKIPPED_FOLDERS + skip` to `@skip = SKIPPED_FOLDERS + skip.map { |folder| folder.chomp("/") }`.
  2. Replace `scan`, `build_classes` and `build_edges` with the code below. `main_constant` is now computed once per file, in `scan`.

```ruby
      def scan
        files = ruby_files
        parsed = files.to_h { |file| [file, Prism.parse_file(File.join(@root, file))] }
        declarations = parsed.to_h { |file, result| [file, Declarations.new(result.value).collect] }
        mains = declarations.reject { |_, found| found[:declared].empty? }
                            .to_h { |file, found| [file, main_constant(file, found[:declared])] }
        classes, aliases = build_classes(parsed, declarations, mains)
        namespaces = declarations.values.flat_map { |found| found[:namespaces] }.to_set
        resolver = Resolver.new(classes: aliases.keys.to_set, namespaces: namespaces)
        edges, foreign = build_edges(parsed, declarations, mains, aliases, resolver)
        {
          "classes" => classes.values.sort_by { |entry| entry["id"] },
          "namespaces" => namespaces.to_a.sort,
          "edges" => edges,
          "skipped" => (files - mains.keys).sort,
          "foreign" => foreign.sort_by { |name, count| [-count, name] }
        }
      end
```

```ruby
      def build_classes(parsed, declarations, mains)
        classes = {}
        aliases = {}
        mains.each do |file, main|
          result = parsed[file]
          own_ids(declarations[file]).each { |id| aliases[id] = main[:id] }
          ops = Operations.new(result.value, file).collect
          if classes.key?(main[:id])
            owner = classes[main[:id]]
            owner["files"] << file
            owner["ops"].concat(ops)
            owner["parse_errors"].concat(parse_errors(result).map { |error| "#{file} #{error}" })
          else
            classes[main[:id]] = {
              "id" => main[:id], "file" => file, "files" => [file], "kind_folder" => kind_folder(file),
              "stereotype" => main[:stereotype], "ops" => ops, "parse_errors" => parse_errors(result)
            }
          end
        end
        classes.each_key { |id| aliases[id] = id }
        [classes, aliases]
      end

      def own_ids(found)
        found[:declared].map { |entry| entry[:id] } + found[:secondary]
      end
```

```ruby
      def build_edges(parsed, declarations, mains, aliases, resolver)
        pairs = Set.new
        foreign = Hash.new(0)
        mains.each do |file, main|
          own = own_ids(declarations[file])
          References.new(parsed[file].value).collect.each do |reference|
            from = own.include?(reference[:owner]) ? aliases[reference[:owner]] : main[:id]
            found = resolver.resolve(reference[:name], nesting: reference[:nesting], enclosing: reference[:nesting].last)
            if found.nil?
              foreign[reference[:name].delete_prefix("::").split("::").first] += 1
            elsif found.first == :class
              to = aliases.fetch(found.last, found.last)
              pairs << [from, to] unless from == to
            end
          end
        end
        edges = pairs.to_a.sort.map { |from, to| { "from" => from, "to" => to, "kind" => "dependency" } }
        [edges, foreign]
      end
```

  3. In `Declarations#walk`, change `when Prism::ConstantWriteNode then declare_constant(node, nesting)` to `when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode then declare_constant(node, nesting)`. Replace `declare_constant` and `wrapper?` with:

```ruby
        def declare_constant(node, nesting)
          written = node.is_a?(Prism::ConstantWriteNode) ? node.name.to_s : Scanner.constant_name(node.target)
          return if written.nil?

          full = Scanner.qualify(written, nesting)
          if data_call?(node.value)
            @declared << { id: full, stereotype: "data" }
          elsif !nesting.empty? || full.include?("::")
            @secondary << full
          end
        end

        def wrapper?(body)
          !body.empty? && body.all? do |child|
            child.is_a?(Prism::ClassNode) || child.is_a?(Prism::ModuleNode) ||
              ((child.is_a?(Prism::ConstantWriteNode) || child.is_a?(Prism::ConstantPathWriteNode)) && data_call?(child.value))
          end
        end
```

  4. In `References`, add this method after `visit_constant_path_node`, so the written constant of `Foo::BAR = 1` is not read as a reference:

```ruby
        def visit_constant_path_write_node(node)
          node.value.accept(self)
        end
```

- [ ] **Step 7: Run the scanner tests and the full suite**

Run: `bundle exec ruby -Itest -Ilib test/scanner_test.rb`
Expected: all pass.

Run: `bundle exec rake test`
Expected: all pass. The new fixture class `Reports::Exporter` adds a member to the `Reports` box; no existing test counts those members.

- [ ] **Step 8: Check that the tests can tell.** In `Operations#settle`, delete the `elsif` branch and run `test/operations_test.rb`. Expected: the `private :a` and `public :a` tests fail. Restore it.

- [ ] **Step 9: Commit**

```bash
git add lib/uml/viewer/operations.rb lib/uml/viewer/scanner.rb lib/uml/viewer.rb test/operations_test.rb test/scanner_test.rb test/fixtures/projects/rails_shapes/app/services/reports/exporter.rb
git commit -m "feat: list each class's ops with visibility, cc, file and lines, and merge them for reopened classes"
```

---

### Task 4: Edge kinds and associations

**Files:**
- Create: `lib/uml/viewer/inflector.rb`
- Modify: `lib/uml/viewer/scanner.rb`, `lib/uml/viewer/resolver.rb`, `lib/uml/viewer.rb`
- Test: `test/inflector_test.rb`, `test/scanner_test.rb`, `test/resolver_test.rb`, `test/graph_test.rb`

**Interfaces:**
- Consumes: `Resolver#resolve` (milestone 1).
- Produces:
  - `Uml::Viewer::Inflector.singularize(String) -> String`, `Uml::Viewer::Inflector.camelize(String) -> String`.
  - `Uml::Viewer::Scanner::KINDS = %w[inheritance implements association dependency]` (strongest first).
  - Each scan edge is `{"from", "to", "kind", "kinds"}`: `kinds` lists every kind found for the pair in `KINDS` order, and `kind` is `kinds.first`.
  - The scan gains `"foreign_edges" => [{"from", "to" => <first segment>, "kind", "kinds"}]` (every unresolved non-association reference, one per pair), `"unresolved" => Integer` and `"polymorphic" => Integer`.

- [ ] **Step 1: Write the failing tests.** `test/inflector_test.rb`:

```ruby
require "test_helper"

module Uml
  module Viewer
    class InflectorTest < TestCase
      def test_each_singularize_rule_in_its_order
        assert_equal "person", Inflector.singularize("people")
        assert_equal "sales_person", Inflector.singularize("sales_people")
        assert_equal "child", Inflector.singularize("children")
        assert_equal "category", Inflector.singularize("categories")
        assert_equal "address", Inflector.singularize("addresses")
        assert_equal "access", Inflector.singularize("accesses")
        assert_equal "box", Inflector.singularize("boxes")
        assert_equal "batch", Inflector.singularize("batches")
        assert_equal "wish", Inflector.singularize("wishes")
        assert_equal "status", Inflector.singularize("statuses")
        assert_equal "user", Inflector.singularize("users")
        assert_equal "user", Inflector.singularize("user")
      end

      def test_camelize_joins_the_snake_parts
        assert_equal "OrderAddress", Inflector.camelize("order_address")
        assert_equal "ShippingBatch", Inflector.camelize(Inflector.singularize("shipping_batches"))
        assert_equal "User", Inflector.camelize("user")
      end
    end
  end
end
```

In `test/scanner_test.rb`, replace `test_a_superclass_is_a_dependency_edge_in_milestone_1` with the tests below, and add the helper `found_edge` next to `edge?`:

```ruby
      def found_edge(from, to, in_scan: scan)
        in_scan["edges"].find { |edge| edge["from"] == from && edge["to"] == to }
      end

      def test_a_superclass_gives_an_inheritance_edge
        assert_equal ["inheritance"], found_edge("User", "ApplicationRecord")["kinds"]
      end

      def test_class_name_as_a_string_wins_over_the_association_name
        assert_equal "association", found_edge("Order", "User")["kind"]
        refute scan["edges"].any? { |edge| edge["to"] == "ApprovedBy" }
      end

      def test_a_compact_model_association_to_a_sibling_merges_with_its_dependency
        edge = found_edge("Shop::Customer", "Shop::Store")
        assert_equal ["association", ["association", "dependency"]], [edge["kind"], edge["kinds"]]
      end

      def test_association_shapes
        root = project(
          "app/models/user.rb" => "class User\nend\n",
          "app/models/tag.rb" => "class Tag\nend\n",
          "app/models/order_address.rb" => "class OrderAddress\nend\n",
          "app/models/shipping_batch.rb" => "class ShippingBatch\nend\n",
          "app/models/order.rb" => <<~RUBY
            class Order
              belongs_to :buyer, class_name: :User
              has_many :tags, through: :taggings
              has_many :order_addresses
              has_many :shipping_batches
            end
          RUBY
        )
        result = Scanner.new(root).scan
        %w[User Tag OrderAddress ShippingBatch].each do |target|
          assert_equal "association", found_edge("Order", target, in_scan: result)&.fetch("kind"), "Order -> #{target}"
        end
      end

      def test_through_with_source_takes_the_target_from_source
        root = project(
          "app/models/user.rb" => "class User\nend\n",
          "app/models/order.rb" => "class Order\n  has_many :buyers, through: :line_items, source: :user\nend\n"
        )
        assert_equal "association", found_edge("Order", "User", in_scan: Scanner.new(root).scan)["kind"]
      end

      def test_polymorphic_and_unresolved_associations_give_no_edge_and_are_counted
        root = project(
          "app/models/user.rb" => "class User\nend\n",
          "app/models/order.rb" => "class Order\n  belongs_to :owner, polymorphic: true\n  has_many :ghosts\n  belongs_to :buyer, class_name: User.name\nend\n"
        )
        result = Scanner.new(root).scan
        assert_equal [1, 2], result.values_at("polymorphic", "unresolved")
        assert_equal ["dependency"], found_edge("Order", "User", in_scan: result)["kinds"]
        assert_equal [["Order", "User"]], result["edges"].map { |edge| [edge["from"], edge["to"]] }
      end

      def test_a_leading_double_colon_in_class_name_forces_the_top_level_class
        root = project(
          "app/models/user.rb" => "class User\nend\n",
          "app/models/shop/user.rb" => "class Shop::User\nend\n",
          "app/models/shop/customer.rb" => "class Shop::Customer\n  belongs_to :owner, class_name: \"::User\"\nend\n"
        )
        result = Scanner.new(root).scan
        assert edge?("Shop::Customer", "User", in_scan: result)
        refute edge?("Shop::Customer", "Shop::User", in_scan: result)
      end

      def test_include_extend_and_prepend_give_implements_edges
        root = project(
          "app/models/concerns/trackable.rb" => "module Trackable\nend\n",
          "app/services/auditing.rb" => "module Auditing\nend\n",
          "app/services/logging.rb" => "module Logging\nend\n",
          "app/models/order.rb" => "class Order\n  include Trackable\n  extend Auditing\n  prepend Logging\nend\n"
        )
        result = Scanner.new(root).scan
        %w[Trackable Auditing Logging].each do |target|
          assert_equal ["implements"], found_edge("Order", target, in_scan: result)&.fetch("kinds"), "Order -> #{target}"
        end
      end

      def test_an_unresolved_reference_gives_a_foreign_edge_to_its_first_segment
        root = project("app/services/pricing.rb" => "class Pricing < Base::Calculator\n  def http = Faraday::Connection.new\nend\n")
        result = Scanner.new(root).scan
        assert_equal [["Pricing", "Base", "inheritance"], ["Pricing", "Faraday", "dependency"]],
                     result["foreign_edges"].map { |edge| edge.values_at("from", "to", "kind") }
      end
```

Add to `test/resolver_test.rb`:

```ruby
      def test_the_strip_step_also_works_on_a_rails_prefix_candidate
        assert_equal [:class, "Shop::Store"],
                     resolver.resolve("Store::KINDS", nesting: ["Shop::Customer"], enclosing: "Shop::Customer")
      end

      def test_a_reference_of_four_segments_strips_down_to_the_class
        assert_equal [:class, "Reports::Summary"],
                     resolver.resolve("Reports::Summary::Row::WIDTH", nesting: ["Order"], enclosing: "Order")
      end

      def test_a_leading_double_colon_tries_only_the_top_level
        resolver = Resolver.new(classes: Set["Order", "Shop::Order"], namespaces: Set["Shop"])
        assert_equal [:class, "Order"], resolver.resolve("::Order", nesting: ["Shop"], enclosing: "Shop")
      end

      def test_the_strip_step_keeps_the_first_written_segment
        assert_nil resolver.resolve("Foo::BAR", nesting: ["Reports", "Reports::Summary"], enclosing: "Reports::Summary")
      end
```

In `test/graph_test.rb`, change the expected hash of `test_the_first_example_of_the_spec_gives_a_red_dependency_from_order_to_reports_summary` to:

```ruby
        assert_equal({ "from" => "Order", "to" => "Reports::Summary", "kind" => "dependency", "kinds" => ["dependency"], "violating" => true },
                     edge("Order", "Reports::Summary"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/inflector_test.rb`
Expected: 2 errors, `uninitialized constant Uml::Viewer::Inflector`.

Run: `bundle exec ruby -Itest -Ilib test/scanner_test.rb`
Expected: the new kind tests fail (`kinds` is nil, `kind` is `dependency`, no association edges, no `foreign_edges`).

Run: `bundle exec ruby -Itest -Ilib test/resolver_test.rb`
Expected: the four new tests pass already (they pin milestone 1 behavior). That is fine: they protect Step 5.

- [ ] **Step 3: Write `lib/uml/viewer/inflector.rb`**

```ruby
module Uml
  module Viewer
    module Inflector
      SINGULAR = [
        [/people\z/, "person"], [/children\z/, "child"], [/ies\z/, "y"], [/sses\z/, "ss"], [/xes\z/, "x"],
        [/ches\z/, "ch"], [/shes\z/, "sh"], [/ses\z/, "s"], [/s\z/, ""]
      ].freeze

      def self.singularize(word)
        pattern, replacement = SINGULAR.find { |rule, _| word.match?(rule) }
        pattern ? word.sub(pattern, replacement) : word
      end

      def self.camelize(word)
        word.split("_").map(&:capitalize).join
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/inflector"` directly after `require_relative "viewer/operations"`.

- [ ] **Step 4: Change the scanner.** In `lib/uml/viewer/scanner.rb`:

  1. Add `KINDS = %w[inheritance implements association dependency].freeze` after `DATA_CALLS`.
  2. Replace `build_edges` and add `merge_kinds`:

```ruby
      def build_edges(parsed, declarations, mains, aliases, resolver)
        kinds = Hash.new { |hash, pair| hash[pair] = Set.new }
        foreign_kinds = Hash.new { |hash, pair| hash[pair] = Set.new }
        foreign = Hash.new(0)
        counts = { "unresolved" => 0, "polymorphic" => 0 }
        mains.each do |file, main|
          own = own_ids(declarations[file])
          references = References.new(parsed[file].value)
          references.collect.each do |reference|
            from = own.include?(reference[:owner]) ? aliases[reference[:owner]] : main[:id]
            found = resolver.resolve(reference[:name], nesting: reference[:nesting], enclosing: reference[:nesting].last)
            if found&.first == :class
              to = aliases.fetch(found.last, found.last)
              kinds[[from, to]] << reference[:kind] unless from == to
            elsif reference[:kind] == "association"
              counts["unresolved"] += 1
            elsif found.nil?
              first = reference[:name].delete_prefix("::").split("::").first
              foreign[first] += 1
              foreign_kinds[[from, first]] << reference[:kind]
            end
          end
          counts["unresolved"] += references.unresolved
          counts["polymorphic"] += references.polymorphic
        end
        [merge_kinds(kinds), merge_kinds(foreign_kinds), foreign, counts]
      end

      def merge_kinds(kinds)
        kinds.sort.map do |(from, to), found|
          ordered = KINDS.select { |kind| found.include?(kind) }
          { "from" => from, "to" => to, "kind" => ordered.first, "kinds" => ordered }
        end
      end
```

  3. In `scan`, change `edges, foreign = build_edges(...)` to `edges, foreign_edges, foreign, counts = build_edges(parsed, declarations, mains, aliases, resolver)`, and return:

```ruby
        {
          "classes" => classes.values.sort_by { |entry| entry["id"] },
          "namespaces" => namespaces.to_a.sort,
          "edges" => edges,
          "foreign_edges" => foreign_edges,
          "skipped" => (files - mains.keys).sort,
          "foreign" => foreign.sort_by { |name, count| [-count, name] },
          "unresolved" => counts["unresolved"],
          "polymorphic" => counts["polymorphic"]
        }
```

  4. Replace the `References` class with:

```ruby
      class References < Prism::Visitor
        ASSOCIATIONS = %i[has_many has_one belongs_to has_and_belongs_to_many].freeze
        PLURAL = %i[has_many has_and_belongs_to_many].freeze
        INCLUSIONS = %i[include extend prepend].freeze

        attr_reader :polymorphic, :unresolved

        def initialize(program)
          @program = program
          @nesting = []
          @found = []
          @kind = "dependency"
          @polymorphic = 0
          @unresolved = 0
          super()
        end

        def collect
          @program.accept(self)
          @found
        end

        def visit_class_node(node)
          with_kind("inheritance") { node.superclass&.accept(self) }
          enter(node) { node.body&.accept(self) }
        end

        def visit_module_node(node)
          enter(node) { node.body&.accept(self) }
        end

        def visit_call_node(node)
          if node.receiver.nil? && INCLUSIONS.include?(node.name)
            with_kind("implements") { node.arguments&.accept(self) }
            node.block&.accept(self)
          else
            associate(node) if association?(node)
            super
          end
        end

        def visit_constant_read_node(node)
          record(node.name.to_s)
        end

        def visit_constant_path_node(node)
          name = Scanner.constant_name(node)
          name.nil? ? super : record(name)
        end

        def visit_constant_path_write_node(node)
          node.value.accept(self)
        end

        private

        def association?(node)
          node.receiver.nil? && ASSOCIATIONS.include?(node.name) && node.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
        end

        def associate(node)
          options = options_of(node)
          if options["polymorphic"].is_a?(Prism::TrueNode)
            @polymorphic += 1
          elsif options.key?("class_name") && literal(options["class_name"]).nil?
            @unresolved += 1
          else
            record(association_target(node, options), kind: "association")
          end
        end

        def association_target(node, options)
          return literal(options["class_name"]) if options.key?("class_name")

          base = literal(options["source"]) || node.arguments.arguments.first.unescaped
          base = Inflector.singularize(base) if PLURAL.include?(node.name)
          Inflector.camelize(base)
        end

        def options_of(node)
          hash = node.arguments.arguments.find { |argument| argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode) }
          return {} if hash.nil?

          hash.elements.filter_map do |element|
            [element.key.unescaped, element.value] if element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
          end.to_h
        end

        def literal(node)
          node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
        end

        def enter(node)
          name = Scanner.constant_name(node.constant_path)
          return yield if name.nil?

          @nesting.push(Scanner.qualify(name, @nesting))
          yield
        ensure
          @nesting.pop unless name.nil?
        end

        def with_kind(kind)
          previous = @kind
          @kind = kind
          yield
        ensure
          @kind = previous
        end

        def record(name, kind: @kind)
          @found << { name: name, nesting: @nesting.dup, owner: @nesting.last, kind: kind }
        end
      end
```

- [ ] **Step 5: Drop the redundant resolver guard.** In `lib/uml/viewer/resolver.rb`, delete the line `return nil if written_size < 2` in `stripped`. The loop `1.upto(written_size - 1)` already does nothing for one segment. Keep `.uniq` in `candidates_for`: lexical and Rails candidates often overlap, and `.uniq` saves the second lookup.

- [ ] **Step 6: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/inflector_test.rb && bundle exec ruby -Itest -Ilib test/scanner_test.rb && bundle exec ruby -Itest -Ilib test/resolver_test.rb`
Expected: all pass.

Run: `bundle exec rake test`
Expected: all pass. The policy tests build their own edges without `kinds`; Policy does not read `kinds` until Task 6.

- [ ] **Step 7: Check that the tests can tell.** In `association_target`, delete the line with `Inflector.singularize`. Run `test/scanner_test.rb`. Expected: `test_association_shapes` fails on `Order -> Tag`. Restore it.

- [ ] **Step 8: Commit**

```bash
git add lib/uml/viewer/inflector.rb lib/uml/viewer/scanner.rb lib/uml/viewer/resolver.rb lib/uml/viewer.rb test/inflector_test.rb test/scanner_test.rb test/resolver_test.rb test/graph_test.rb
git commit -m "feat: scan inheritance, implements and association edges, count unresolved and polymorphic associations"
```

---

### Task 5: ActiveAdmin pseudo-classes

**Files:**
- Create: `test/fixtures/projects/rails_shapes/app/admin/orders.rb`, `test/fixtures/projects/rails_shapes/app/admin/customers.rb`
- Modify: `lib/uml/viewer/scanner.rb`, `lib/uml/viewer/policy.rb`, `lib/uml/viewer/web/app.js`
- Test: `test/scanner_test.rb`, `test/policy_test.rb`, `test/browser_test.rb`

**Interfaces:**
- Consumes: the scan of Task 4.
- Produces:
  - A file with a top-level `ActiveAdmin.register X` (with or without `as:`) declares the class `ActiveAdmin(X)`, with `kind_folder` `admin` and `stereotype` `admin`. Its `dependency` edge to `X` comes from the normal reference scan. Two files that register the same `X` are one reopened class.
  - `Policy.segments(entry) -> [String]`: `[entry["id"]]` for an admin class, else `entry["id"].split("::")`. Later tasks place classes with it.
  - Each box member is `{"id", "type", "label"}`; `label` is the last segment, or the full id for an admin class. The page shows `label`.

- [ ] **Step 1: Write the fixture files**

`test/fixtures/projects/rails_shapes/app/admin/orders.rb`:

```ruby
ActiveAdmin.register Order do
  permit_params :state
end
```

`test/fixtures/projects/rails_shapes/app/admin/customers.rb`:

```ruby
ActiveAdmin.register Shop::Customer, as: "Client" do
  index { Pricing }
end
```

- [ ] **Step 2: Write the failing tests.** Add to `test/scanner_test.rb`:

```ruby
      def test_an_active_admin_register_block_is_an_admin_pseudo_class_with_a_dependency_on_its_model
        admin = klass("ActiveAdmin(Order)")
        assert_equal ["admin", "admin", "app/admin/orders.rb"], admin.values_at("kind_folder", "stereotype", "file")
        assert_equal ["dependency"], found_edge("ActiveAdmin(Order)", "Order")["kinds"]
      end

      def test_an_active_admin_block_with_as_and_a_namespaced_model_keeps_the_model_name_in_its_id
        assert klass("ActiveAdmin(Shop::Customer)")
        assert edge?("ActiveAdmin(Shop::Customer)", "Shop::Customer")
        assert edge?("ActiveAdmin(Shop::Customer)", "Pricing")
      end

      def test_an_active_admin_page_without_a_model_is_skipped
        root = project("app/admin/dashboard.rb" => "ActiveAdmin.register_page \"Dashboard\" do\nend\n")
        assert_equal ["app/admin/dashboard.rb"], Scanner.new(root).scan["skipped"]
      end
```

Add to `test/policy_test.rb`. First extend the `scan` helper so a class can carry a stereotype: change the class mapping to

```ruby
          "classes" => classes.map { |id, folder| { "id" => id, "kind_folder" => folder, "file" => "x.rb", "files" => ["x.rb"], "stereotype" => id.start_with?("ActiveAdmin(") ? "admin" : "class", "ops" => [], "parse_errors" => [] } },
```

Then add:

```ruby
      def test_an_admin_class_with_a_namespaced_model_sits_in_the_admin_kind_box_with_its_full_id_as_label
        graph = apply(scan({ "ActiveAdmin(Shop::Customer)" => "admin", "Shop::Customer" => "models" }, [], ["Shop"]))
        box = graph["boxes"].find { |b| b["id"] == "folder:admin" }
        assert_equal [{ "id" => "ActiveAdmin(Shop::Customer)", "type" => "class", "label" => "ActiveAdmin(Shop::Customer)" }], box["members"]
        assert_equal ["Shop", "folder:admin"], graph["boxes"].map { |b| b["id"] }.sort
      end

      def test_omit_of_the_admin_kind_box_removes_an_admin_class_with_a_namespaced_model
        graph = apply(scan({ "ActiveAdmin(Shop::Customer)" => "admin", "Shop::Customer" => "models" }, [], ["Shop"]), "omit" => ["folder:admin"])
        assert_equal ["Shop::Customer"], graph["classes"].map { |c| c["id"] }
      end
```

In the existing tests of `test/policy_test.rb` that compare `members`, add the label to each expected member: `{ "id" => "Billing::Counter", "type" => "class", "label" => "Counter" }`, `{ "id" => "Billing::Gateway", "type" => "namespace", "label" => "Gateway" }`, `{ "id" => "Payments", "type" => "class", "label" => "Payments" }`, `{ "id" => "Order", "type" => "class", "label" => "Order" }`.

Add to `test/browser_test.rb`:

```ruby
      def test_the_admin_kind_box_lists_an_admin_class_by_its_full_id
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:admin"]')
        assert_equal "ActiveAdmin(Shop::Customer)", @browser.at_css('text.member[data-id="ActiveAdmin(Shop::Customer)"]').text
      end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/scanner_test.rb -n /active_admin/`
Expected: 3 failures; the admin files are skipped (no constant), so `klass("ActiveAdmin(Order)")` is nil and `skipped` holds three files.

Run: `bundle exec ruby -Itest -Ilib test/policy_test.rb`
Expected: the admin test fails (the class sits in a `ActiveAdmin(Shop` box); the member tests fail on the missing `label`.

- [ ] **Step 4: Declare the pseudo-class.** In `lib/uml/viewer/scanner.rb`:

  1. In `Declarations#walk`, add a branch: `when Prism::CallNode then declare_admin(node)`.
  2. Add to `Declarations` (private):

```ruby
        def declare_admin(node)
          return unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :ActiveAdmin && node.name == :register

          model = Scanner.constant_name(node.arguments&.arguments&.first)
          @declared << { id: "ActiveAdmin(#{model.delete_prefix('::')})", stereotype: "admin" } if model
        end
```

  3. In `build_classes`, change `"kind_folder" => kind_folder(file)` to `"kind_folder" => main[:stereotype] == "admin" ? "admin" : kind_folder(file)`.

- [ ] **Step 5: Place the admin class and label the members.** In `lib/uml/viewer/policy.rb`:

  1. Add:

```ruby
      def self.segments(entry)
        entry["stereotype"] == "admin" ? [entry["id"]] : entry["id"].split("::")
      end

      def self.label(entry)
        segments(entry).last
      end
```

  2. Replace `in_namespace_box?` and `box_id` with:

```ruby
      def self.in_namespace_box?(entry, namespaces)
        segments(entry).size > 1 || namespaces.include?(entry["id"])
      end

      def self.box_id(entry, namespaces)
        found = segments(entry)
        return found.first if found.size > 1
        return entry["id"] if namespaces.include?(entry["id"])

        "folder:#{entry['kind_folder']}"
      end
```

  3. In `apply`, change `!in_namespace_box?(entry["id"], namespaces)` to `!in_namespace_box?(entry, namespaces)`.
  4. In `boxes`, change the member-class selection and the members:

```ruby
          member_classes = members.select { |entry| folder || entry["id"] == id || (segments(entry).size == 2 && !namespaces.include?(entry["id"])) }
                                  .map { |entry| { "id" => entry["id"], "type" => "class", "label" => label(entry) } }
          child_namespaces = folder ? [] : namespaces.select { |name| name.start_with?("#{id}::") && name.split("::").size == 2 }
                                                     .map { |name| { "id" => name, "type" => "namespace", "label" => name.split("::").last } }
```

- [ ] **Step 6: Show the label on the page.** In `lib/uml/viewer/web/app.js`, in `boxLines`, change `shortName(member.id)` to `member.label`, and delete the now unused `shortName` constant.

- [ ] **Step 7: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/scanner_test.rb && bundle exec ruby -Itest -Ilib test/policy_test.rb && bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: all pass.

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/uml/viewer/scanner.rb lib/uml/viewer/policy.rb lib/uml/viewer/web/app.js test/scanner_test.rb test/policy_test.rb test/browser_test.rb test/fixtures/projects/rails_shapes/app/admin
git commit -m "feat: show each ActiveAdmin register block as an admin pseudo-class in the admin kind box"
```

---

### Task 6: Kinds in the policy, foreign edges, warnings and PolicyFile checks

**Files:**
- Modify: `lib/uml/viewer/policy.rb`, `lib/uml/viewer/policy_file.rb`, `lib/uml/viewer/graph.rb`
- Test: `test/policy_test.rb`, `test/policy_file_test.rb`, `test/graph_test.rb`

**Interfaces:**
- Consumes: scan edges with `kinds` and the scan keys `foreign_edges`, `unresolved`, `polymorphic` (Task 4).
- Produces:
  - An edge is violating when both ends have a level, the level of `from` is lower than the level of `to`, and one of its `kinds` is not `association`.
  - `edge_kinds` sets both `kind` and `kinds` (`[kind]`) of the pair.
  - `Policy.apply` also returns `"foreign_edges"` (the scan's foreign edges whose `to` is in `foreign:` and whose `from` is kept) and `"warnings"` (`"levels: unknown folder <name>"` for each folder in `levels:` that no scanned class has).
  - `graph["summary"]` gains `"unresolved"`, `"polymorphic"` and `"warnings"`.
  - `PolicyFile.load` raises `Invalid` with `policy.yml: edge_kinds maps "From -> To" to one of inheritance, implements, association, dependency` for a bad key or value, and `policy.yml: title must be text` for a title that is not a string.

- [ ] **Step 1: Write the failing tests.** In `test/policy_test.rb`, change the `scan` helper so an edge can carry kinds, and give the scan its foreign edges:

```ruby
      def scan(classes, edges, namespaces = [], foreign_edges: [])
        {
          "classes" => classes.map { |id, folder| { "id" => id, "kind_folder" => folder, "file" => "x.rb", "files" => ["x.rb"], "stereotype" => id.start_with?("ActiveAdmin(") ? "admin" : "class", "ops" => [], "parse_errors" => [] } },
          "edges" => edges.map { |from, to, kinds = ["dependency"]| { "from" => from, "to" => to, "kind" => kinds.first, "kinds" => kinds } },
          "foreign_edges" => foreign_edges.map { |from, to| { "from" => from, "to" => to, "kind" => "dependency", "kinds" => ["dependency"] } },
          "namespaces" => namespaces
        }
      end
```

Add:

```ruby
      def test_an_association_alone_is_never_violating_across_levels
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing", ["association"]]]))
        refute graph["edges"].first["violating"]
      end

      def test_inheritance_and_implements_are_violating_across_levels
        graph = apply(scan({ "Order" => "models", "Base" => "services", "Audit" => "services" },
                           [["Order", "Base", ["inheritance"]], ["Order", "Audit", ["implements"]]]))
        assert_equal [true, true], graph["edges"].map { |edge| edge["violating"] }
      end

      def test_a_merged_pair_shown_as_association_is_violating_when_it_also_has_a_dependency
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing", ["association", "dependency"]]]))
        assert_equal ["association", true], graph["edges"].first.values_at("kind", "violating")
      end

      def test_edge_kinds_replaces_every_kind_of_the_pair
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing", ["association", "dependency"]]]),
                      "edge_kinds" => { "Order -> Pricing" => "association" })
        assert_equal ["association", ["association"], false], graph["edges"].first.values_at("kind", "kinds", "violating")
      end

      def test_only_foreign_edges_to_a_listed_name_and_from_a_kept_class_stay
        input = scan({ "Order" => "models", "Pricing" => "services" }, [], foreign_edges: [["Order", "Faraday"], ["Order", "JSON"], ["Pricing", "Faraday"]])
        graph = apply(input, "foreign" => ["Faraday"], "omit" => ["Pricing"])
        assert_equal [["Order", "Faraday"]], graph["foreign_edges"].map { |edge| edge.values_at("from", "to") }
      end

      def test_a_level_folder_that_no_class_has_gives_a_warning
        graph = apply(scan({ "Order" => "models" }, []), "levels" => [["models"], ["workers"]])
        assert_equal ["levels: unknown folder workers"], graph["warnings"]
      end
```

Add to `test/policy_file_test.rb` (the file's helper `write(text)` writes a temp `policy.yml` and returns its path):

```ruby
      def test_an_edge_kinds_value_that_is_no_kind_raises_with_the_rule
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("edge_kinds:\n  \"Order -> User\": friend\n")) }
        assert_equal 'policy.yml: edge_kinds maps "From -> To" to one of inheritance, implements, association, dependency', error.message
      end

      def test_an_edge_kinds_key_without_an_arrow_raises_with_the_rule
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("edge_kinds:\n  Order: association\n")) }
        assert_match(/\Apolicy\.yml: edge_kinds maps/, error.message)
      end

      def test_a_valid_edge_kinds_entry_loads
        assert_equal({ "Order -> User" => "association" }, PolicyFile.load(write("edge_kinds:\n  \"Order -> User\": association\n"))["edge_kinds"])
      end

      def test_a_title_that_is_not_text_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("title: 12\n")) }
        assert_equal "policy.yml: title must be text", error.message
      end

      def test_a_syntax_error_names_the_line_psych_reports
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("title: x\nsources: [app]\nlevels: [\n")) }
        assert_equal "policy.yml line 4: did not find expected node content", error.message
      end
```

Add to `test/graph_test.rb`:

```ruby
      def test_the_summary_counts_associations_and_lists_warnings
        summary = graph["summary"]
        assert_equal [0, 0, []], summary.values_at("unresolved", "polymorphic", "warnings")
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/policy_test.rb && bundle exec ruby -Itest -Ilib test/policy_file_test.rb && bundle exec ruby -Itest -Ilib test/graph_test.rb`
Expected: `test_an_association_alone_is_never_violating_across_levels` passes already (kind is `association`); the merged-pair test fails (`violating` false); `edge_kinds` replaces `kind` only; `foreign_edges` and `warnings` are nil; the edge_kinds and title tests get no exception; the line test passes already (it pins the line); the summary test fails on nil counts.

- [ ] **Step 3: Change the policy.** In `lib/uml/viewer/policy.rb`:

  1. Replace `violating?`:

```ruby
      def self.violating?(edge, by_id)
        from = by_id[edge["from"]]["level"]
        to = by_id[edge["to"]]["level"]
        return false if from.nil? || to.nil? || from >= to

        edge["kinds"].any? { |kind| kind != "association" }
      end
```

  2. In `adjust_edges`, change the merge to `edge.merge("kind" => edge_kinds[pair_key(edge)], "kinds" => [edge_kinds[pair_key(edge)]])`.
  3. Delete the `kept` map in `apply`; use `by_id` for the edge filter. Build `by_id` before the edges, from the classes with levels. In the returned hash add:

```ruby
          "foreign_edges" => scan["foreign_edges"].select { |edge| policy["foreign"].include?(edge["to"]) && by_id.key?(edge["from"]) },
          "warnings" => (policy["levels"].flatten.uniq - scan["classes"].map { |entry| entry["kind_folder"] }).map { |name| "levels: unknown folder #{name}" }
```

- [ ] **Step 4: Validate the policy file.** In `lib/uml/viewer/policy_file.rb`, in `validate`, after the `edge_kinds must be a mapping` check, add:

```ruby
        unless policy["edge_kinds"].all? { |pair, kind| pair.is_a?(String) && pair.match?(/\A\S+ -> \S+\z/) && Scanner::KINDS.include?(kind) }
          raise Invalid, "policy.yml: edge_kinds maps \"From -> To\" to one of #{Scanner::KINDS.join(', ')}"
        end
        raise Invalid, "policy.yml: title must be text" unless policy["title"].is_a?(String)
```

- [ ] **Step 5: Add the counts to the summary.** In `lib/uml/viewer/graph.rb`, replace the `"summary"` entry with `"summary" => summary(scan, applied, policy)` and add:

```ruby
      def self.summary(scan, applied, policy)
        {
          "classes" => applied["classes"].size,
          "skipped" => scan["skipped"],
          "foreign" => scan["foreign"].reject { |name, _| policy["foreign"].include?(name) }.first(20),
          "unresolved" => scan["unresolved"],
          "polymorphic" => scan["polymorphic"],
          "warnings" => applied["warnings"]
        }
      end
```

Change `policy["title"].to_s.empty?` to `policy["title"].empty?`: the title is now always a string. Remove `"foreign_edges"` and `"warnings"` from the hash that `Graph.build` merges from `applied`, so they do not land at the top level of `graph.json`: change `}.merge(applied)` to `}.merge(applied.slice("classes", "edges", "boxes", "arrows"))`.

- [ ] **Step 6: Run the tests**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/uml/viewer/policy.rb lib/uml/viewer/policy_file.rb lib/uml/viewer/graph.rb test/policy_test.rb test/policy_file_test.rb test/graph_test.rb
git commit -m "feat: flag a merged edge red when any non-association kind breaks the levels, and validate edge_kinds and title"
```

---

### Task 7: Views, graph version 2 and command kinds

**Files:**
- Create: `lib/uml/viewer/views.rb`
- Modify: `lib/uml/viewer/policy.rb`, `lib/uml/viewer/graph.rb`, `lib/uml/viewer/commands.rb`, `lib/uml/viewer/web/app.js`, `lib/uml/viewer.rb`
- Test: `test/views_test.rb`, `test/policy_test.rb`, `test/graph_test.rb`, `test/commands_test.rb`, `test/server_test.rb`

**Interfaces:**
- Consumes: `Policy.segments(entry)` (Task 5); `Policy.apply` output (Task 6).
- Produces:
  - `Uml::Viewer::Views.build(classes, namespaces, edges, foreign_edges) -> {view_id => view}`. View ids: `"root"`, each namespace id, each `"folder:<kind>"`. A view is `{"id", "label", "parent", "nodes", "arrows"}`; `parent` is `nil` for root.
  - A node is one of:
    - container: `{"id", "type" => "namespace"|"folder", "label", "levels" => [min, max]|nil, "members" => [{"id", "type", "label"}]}`; `members` are the nodes of that container's own view.
    - class: `{"id", "type" => "class", "label", "stereotype", "level", "levels" => [l, l]|nil}`.
    - foreign (root view only): `{"id" => "foreign:<Name>", "type" => "foreign", "label" => "<Name>", "levels" => nil}`.
  - An arrow is `{"from", "to", "violating", "pairs" => [{"from", "to", "kind", "violating"}]}`, between two nodes of the same view.
  - `Policy.apply` returns `"views"` instead of `"boxes"` and `"arrows"`, and `"namespaces"` (only the namespaces that still hold a kept class).
  - `graph.json` is `{"version" => 2, "title", "proposals", "summary", "namespaces", "classes", "edges", "views"}`.
  - `Graph.ids(graph) -> {"class" => Set, "box" => Set}`. `Commands.validate(body, ids:, proposal_ids:)` takes that hash and checks a target id in the set of its kind.

- [ ] **Step 1: Write the failing tests.** `test/views_test.rb`:

```ruby
require "test_helper"

module Uml
  module Viewer
    class ViewsTest < TestCase
      def entry(id, folder, level, stereotype: "class")
        { "id" => id, "kind_folder" => folder, "level" => level, "stereotype" => stereotype }
      end

      def edge(from, to, violating: false, kind: "dependency")
        { "from" => from, "to" => to, "kind" => kind, "violating" => violating }
      end

      def ids(view)
        view["nodes"].map { |node| node["id"] }
      end

      def test_a_namespace_view_holds_its_child_namespaces_and_its_classes_and_names_its_parent
        views = Views.build([entry("Billing::Counter", "services", 1), entry("Billing::Gateway::Client", "services", 1)], ["Billing", "Billing::Gateway"], [], [])
        assert_equal ["Billing"], ids(views["root"])
        assert_equal ["Billing::Counter", "Billing::Gateway"], ids(views["Billing"])
        assert_equal ["Billing::Gateway::Client"], ids(views["Billing::Gateway"])
        assert_equal ["root", "Billing", "Gateway"], [views["Billing"]["parent"], views["Billing::Gateway"]["parent"], views["Billing::Gateway"]["label"]]
      end

      def test_an_edge_shows_once_in_the_view_where_the_two_paths_split
        classes = [entry("Billing::Gateway::Client", "services", 1), entry("Billing::Counter", "services", 1), entry("Order", "models", 0)]
        views = Views.build(classes, ["Billing", "Billing::Gateway"],
                            [edge("Billing::Gateway::Client", "Billing::Counter"), edge("Billing::Counter", "Order")], [])
        assert_equal [["Billing::Gateway", "Billing::Counter"]], views["Billing"]["arrows"].map { |arrow| arrow.values_at("from", "to") }
        assert_equal [["Billing", "folder:models"]], views["root"]["arrows"].map { |arrow| arrow.values_at("from", "to") }
        assert_empty views["Billing::Gateway"]["arrows"]
      end

      def test_a_class_with_the_id_of_a_namespace_is_a_class_node_inside_that_namespace_view
        views = Views.build([entry("Payments", "services", 1), entry("Payments::Gateway", "services", 1)], ["Payments"], [edge("Payments", "Payments::Gateway")], [])
        assert_equal [["Payments", "namespace"]], views["root"]["nodes"].map { |node| node.values_at("id", "type") }
        assert_equal [["Payments", "class"], ["Payments::Gateway", "class"]], views["Payments"]["nodes"].map { |node| node.values_at("id", "type") }
        assert_equal [["Payments", "Payments::Gateway"]], views["Payments"]["arrows"].map { |arrow| arrow.values_at("from", "to") }
      end

      def test_a_top_level_class_sits_in_its_kind_box_view
        views = Views.build([entry("Order", "models", 0)], [], [], [])
        assert_equal [["folder:models", "folder", "models"]], views["root"]["nodes"].map { |node| node.values_at("id", "type", "label") }
        assert_equal ["Order"], ids(views["folder:models"])
      end

      def test_an_admin_class_with_a_namespaced_model_stays_in_the_admin_kind_box
        views = Views.build([entry("ActiveAdmin(Shop::Customer)", "admin", 3, stereotype: "admin"), entry("Shop::Customer", "models", 0)], ["Shop"], [], [])
        assert_equal ["Shop", "folder:admin"], ids(views["root"])
        assert_equal [["ActiveAdmin(Shop::Customer)", "ActiveAdmin(Shop::Customer)"]], views["folder:admin"]["nodes"].map { |node| node.values_at("id", "label") }
        refute views.key?("ActiveAdmin(Shop")
      end

      def test_a_foreign_edge_gives_an_oval_and_an_arrow_on_the_first_screen_only
        views = Views.build([entry("Billing::Client", "services", 1)], ["Billing"], [], [{ "from" => "Billing::Client", "to" => "Faraday", "kind" => "dependency" }])
        oval = views["root"]["nodes"].find { |node| node["id"] == "foreign:Faraday" }
        assert_equal ["foreign", "Faraday", nil], oval.values_at("type", "label", "levels")
        arrow = views["root"]["arrows"].first
        assert_equal ["Billing", "foreign:Faraday", false], arrow.values_at("from", "to", "violating")
        assert_equal [{ "from" => "Billing::Client", "to" => "Faraday", "kind" => "dependency", "violating" => false }], arrow["pairs"]
        assert_empty views["Billing"]["arrows"]
      end

      def test_an_arrow_is_violating_when_one_pair_is_and_each_pair_keeps_its_kind_and_flag
        classes = [entry("Order", "models", 0), entry("User", "models", 0), entry("Pricing", "services", 1)]
        views = Views.build(classes, [], [edge("Order", "Pricing", violating: true), edge("User", "Pricing", kind: "association")], [])
        arrow = views["root"]["arrows"].first
        assert arrow["violating"]
        assert_equal [["Order", "Pricing", "dependency", true], ["User", "Pricing", "association", false]],
                     arrow["pairs"].map { |pair| pair.values_at("from", "to", "kind", "violating") }
      end

      def test_a_container_shows_the_level_range_of_its_classes_and_a_class_node_its_level
        views = Views.build([entry("Reports::Summary", "services", 1), entry("Reports::Page", "controllers", 3), entry("Reports::Row", "workers", nil)], ["Reports"], [], [])
        assert_equal [1, 3], views["root"]["nodes"].first["levels"]
        by_id = views["Reports"]["nodes"].to_h { |node| [node["id"], node] }
        assert_equal [[1, 1], 1], by_id["Reports::Summary"].values_at("levels", "level")
        assert_equal [nil, nil], by_id["Reports::Row"].values_at("levels", "level")
      end

      def test_the_members_of_a_container_are_the_nodes_of_its_view
        views = Views.build([entry("Billing::Counter", "services", 1), entry("Billing::Gateway::Client", "services", 1)], ["Billing", "Billing::Gateway"], [], [])
        assert_equal [{ "id" => "Billing::Counter", "type" => "class", "label" => "Counter" }, { "id" => "Billing::Gateway", "type" => "namespace", "label" => "Gateway" }],
                     views["root"]["nodes"].first["members"]
      end

      def test_no_classes_give_an_empty_root_view
        assert_equal({ "root" => { "id" => "root", "label" => nil, "parent" => nil, "nodes" => [], "arrows" => [] } }, Views.build([], [], [], []))
      end
    end
  end
end
```

Convert `test/policy_test.rb` to views. Add the helpers

```ruby
      def root_nodes(graph) = graph["views"]["root"]["nodes"]
      def root_arrows(graph) = graph["views"]["root"]["arrows"]
```

and in every existing test replace `graph["boxes"]` with `root_nodes(graph)` and `graph["arrows"]` with `root_arrows(graph)`. A pair is now a hash, so compare pairs through `.map { |pair| pair.values_at("from", "to") }`. For example, `assert_equal [["Order", "Pricing"], ["User", "Pricing"]], graph["arrows"].first["pairs"]` becomes `assert_equal [["Order", "Pricing"], ["User", "Pricing"]], root_arrows(graph).first["pairs"].map { |pair| pair.values_at("from", "to") }`. Add one test for the omitted-namespace backlog item:

```ruby
      def test_an_omitted_namespace_leaves_the_namespace_list
        graph = apply(scan({ "Order" => "models", "Reports::Summary" => "services" }, [], ["Reports"]), "omit" => ["Reports"])
        assert_empty graph["namespaces"]
      end
```

In `test/graph_test.rb`:

  - In `test_a_model_depending_on_a_top_level_service_shows_as_a_red_arrow_between_kind_boxes`, read the arrow from `graph["views"]["root"]["arrows"]` and assert `assert_includes arrow["pairs"].map { |pair| pair.values_at("from", "to") }, ["Order", "Pricing"]`.
  - Replace `test_ids_hold_classes_boxes_and_namespaces` with:

```ruby
      def test_ids_hold_class_ids_and_box_ids_apart
        ids = Graph.ids(graph)
        assert_includes ids["class"], "Order"
        assert_includes ids["box"], "folder:models"
        assert_includes ids["box"], "Reports"
        refute_includes ids["class"], "folder:models"
      end

      def test_graph_json_is_version_2_with_views_and_no_boxes
        assert_equal [2, true, false], [graph["version"], graph["views"].key?("Reports"), graph.key?("boxes")]
      end
```

In `test/commands_test.rb`, change `IDS` to `{ "class" => Set["Order"], "box" => Set["folder:models", "Reports"] }.freeze` and add:

```ruby
      def test_a_box_id_sent_with_kind_class_is_refused
        assert_equal "unknown target: folder:models",
                     validate({ "op" => "omit", "target" => { "id" => "folder:models", "kind" => "class", "proposal_id" => nil } }).last
      end
```

In `test/server_test.rb`, in `test_a_policy_change_rescans_and_the_omitted_box_leaves_the_graph`, change `["boxes"].none?` to `["views"]["root"]["nodes"].none?`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/views_test.rb`
Expected: 10 errors, `uninitialized constant Uml::Viewer::Views`.

Run: `bundle exec rake test`
Expected: the policy, graph, commands and server tests fail on the missing `views` and on the ids hash.

- [ ] **Step 3: Write `lib/uml/viewer/views.rb`**

```ruby
require "set"

module Uml
  module Viewer
    module Views
      def self.build(classes, namespaces, edges, foreign_edges)
        known = namespaces.to_set
        paths = classes.to_h { |entry| [entry["id"], path(entry, known)] }
        views = { "root" => view("root", nil, nil) }
        classes.each { |entry| place(views, paths[entry["id"]], entry) }
        foreign_edges.map { |edge| edge["to"] }.uniq.each do |name|
          views["root"]["nodes"]["foreign:#{name}"] = { "id" => "foreign:#{name}", "type" => "foreign", "label" => name, "levels" => nil }
        end
        edges.each { |edge| add_arrow(views, paths[edge["from"]], paths[edge["to"]], edge) }
        foreign_edges.each do |edge|
          add_arrow(views, paths[edge["from"]], [["foreign", "foreign:#{edge['to']}"]], edge.merge("violating" => false))
        end
        views.transform_values { |entry| finish(entry, views) }
      end

      def self.path(entry, namespaces)
        segments = Policy.segments(entry)
        containers = (1...segments.size).map { |count| ["namespace", segments.first(count).join("::")] }
        containers << ["namespace", entry["id"]] if namespaces.include?(entry["id"])
        containers = [["folder", "folder:#{entry['kind_folder']}"]] if containers.empty?
        containers + [["class", entry["id"]]]
      end

      def self.view(id, label, parent)
        { "id" => id, "label" => label, "parent" => parent, "nodes" => {}, "arrows" => {} }
      end

      def self.place(views, path, entry)
        parent = "root"
        path.each do |type, id|
          node = views[parent]["nodes"][id] ||= node(type, id, entry)
          node["levels"] = widen(node["levels"], entry["level"])
          next if type == "class"

          views[id] ||= view(id, node["label"], parent)
          parent = id
        end
      end

      def self.node(type, id, entry)
        case type
        when "class"
          { "id" => id, "type" => "class", "label" => Policy.label(entry), "stereotype" => entry["stereotype"], "level" => entry["level"], "levels" => nil }
        when "folder" then { "id" => id, "type" => "folder", "label" => id.delete_prefix("folder:"), "levels" => nil }
        else { "id" => id, "type" => "namespace", "label" => id.split("::").last, "levels" => nil }
        end
      end

      def self.widen(levels, level)
        return levels if level.nil?
        return [level, level] if levels.nil?

        [[levels[0], level].min, [levels[1], level].max]
      end

      def self.add_arrow(views, from_path, to_path, edge)
        index = (0...[from_path.size, to_path.size].min).find { |position| from_path[position] != to_path[position] }
        view_id = index.zero? ? "root" : from_path[index - 1][1]
        key = [from_path[index][1], to_path[index][1]]
        arrow = views[view_id]["arrows"][key] ||= { "from" => key[0], "to" => key[1], "violating" => false, "pairs" => [] }
        arrow["violating"] ||= edge["violating"]
        arrow["pairs"] << { "from" => edge["from"], "to" => edge["to"], "kind" => edge["kind"], "violating" => edge["violating"] }
      end

      def self.finish(entry, views)
        nodes = entry["nodes"].values.sort_by { |node| node["id"] }.map do |node|
          next node unless %w[namespace folder].include?(node["type"])

          members = views[node["id"]]["nodes"].values.sort_by { |member| member["id"] }
          node.merge("members" => members.map { |member| member.slice("id", "type", "label") })
        end
        arrows = entry["arrows"].values.sort_by { |arrow| [arrow["from"], arrow["to"]] }
                                .map { |arrow| arrow.merge("pairs" => arrow["pairs"].sort_by { |pair| [pair["from"], pair["to"]] }) }
        entry.merge("nodes" => nodes, "arrows" => arrows)
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/views"` directly after `require_relative "viewer/policy"`.

- [ ] **Step 4: Use the views in Policy and Graph.** In `lib/uml/viewer/policy.rb`:

  1. Compute `namespaces` from the kept classes and without omitted names:

```ruby
        namespaces = scan["namespaces"].select { |name| classes.any? { |entry| Policy.segments(entry).size > 1 && entry["id"].start_with?("#{name}::") } }
```

  2. Replace `"boxes" => ...` and `"arrows" => ...` in the returned hash with `"namespaces" => namespaces` and `"views" => Views.build(classes, namespaces, edges, foreign_edges)`, where `foreign_edges` is the local you build for the `"foreign_edges"` entry.
  3. Delete `box_id`, `boxes` and `arrows`. Rename `in_namespace_box?` to `top_level?` with the opposite meaning, so the folder omit reads well:

```ruby
      def self.top_level?(entry, namespaces)
        segments(entry).size == 1 && !namespaces.include?(entry["id"])
      end
```

and use `omit.include?("folder:#{entry['kind_folder']}") && top_level?(entry, namespaces)` in `apply`.

In `lib/uml/viewer/graph.rb`, build the graph as:

```ruby
        graph = {
          "version" => 2,
          "title" => policy["title"].empty? ? File.basename(workspace.root) : policy["title"],
          "proposals" => policy["proposals"],
          "summary" => summary(scan, applied, policy),
          "namespaces" => applied["namespaces"],
          "classes" => applied["classes"],
          "edges" => applied["edges"],
          "views" => applied["views"]
        }
```

and replace `ids`:

```ruby
      def self.ids(graph)
        boxes = graph["views"].values.flat_map { |view| view["nodes"] }
                              .select { |node| %w[namespace folder].include?(node["type"]) }.map { |node| node["id"] }
        { "class" => Set.new(graph["classes"].map { |entry| entry["id"] }), "box" => Set.new(boxes) }
      end
```

- [ ] **Step 5: Check the id against its kind.** In `lib/uml/viewer/commands.rb`, in `check_target`, change `return "unknown target: #{target['id']}" unless ids.include?(target["id"])` to `return "unknown target: #{target['id']}" unless ids.fetch(target["kind"]).include?(target["id"])`.

- [ ] **Step 6: Draw the root view.** In `lib/uml/viewer/web/app.js`, in `draw`:
  - change `graph.boxes.map((box) => {` to `graph.views.root.nodes.map((box) => {`;
  - change both uses of `graph.arrows` to `graph.views.root.arrows`;
  - in `boxLines`, change `box.members.slice` and `box.members.length` to `(box.members || []).slice` and `(box.members || []).length`;
  - change the arrow title to `arrow.pairs.map((pair) => \`${pair.from} -> ${pair.to} (${pair.kind})\`).join("\n")`.

Task 10 replaces this drawing with the full view drawing.

- [ ] **Step 7: Run the tests**

Run: `bundle exec rake test`
Expected: all pass, browser tests included.

- [ ] **Step 8: Check that the tests can tell.** In `Views.add_arrow`, change `view_id = index.zero? ? "root" : from_path[index - 1][1]` to `view_id = "root"`. Run `test/views_test.rb`. Expected: the split test and the class-and-namespace test fail. Restore it.

- [ ] **Step 9: Commit**

```bash
git add lib/uml/viewer/views.rb lib/uml/viewer/policy.rb lib/uml/viewer/graph.rb lib/uml/viewer/commands.rb lib/uml/viewer/web/app.js lib/uml/viewer.rb test/views_test.rb test/policy_test.rb test/graph_test.rb test/commands_test.rb test/server_test.rb
git commit -m "feat: build one view per box with its nodes and collapsed arrows, and check command ids by kind"
```

---

### Task 8: Scan summary in the CLI, and smoke

**Files:**
- Modify: `lib/uml/viewer/cli.rb`, `lib/uml/viewer/smoke.rb`
- Test: `test/cli_test.rb`, `test/smoke_test.rb`

**Interfaces:**
- Consumes: `graph["summary"]` with `unresolved`, `polymorphic`, `warnings` (Task 6).
- Produces:
  - `uml-viewer scan` prints, in this order: the counts line (unchanged), `"N unresolved associations, N polymorphic associations (no target)"`, the `unlisted foreign:` line (unchanged), then one `"warning: <text>"` line per warning.
  - `Smoke.run(paths, out:, &between)` prints each violating edge as `"  <from> -> <to> (<kind>)"` under the counts line; checks git status also when the scan raises; fails a folder that is not a git repository; accepts an empty `expect.yml`; fails a non-list `expect.yml`.

- [ ] **Step 1: Write the failing tests.** Add to `test/cli_test.rb`:

```ruby
      def test_scan_prints_the_association_counts_and_each_warning
        File.write(File.join(@project, "app/models/ghost_owner.rb"), "class GhostOwner\n  has_many :ghosts\n  belongs_to :owner, polymorphic: true\nend\n")
        run_cli("init", @project)
        workspace = Workspace.new(@project)
        workspace.write_atomic("policy.yml", File.read(workspace.path("policy.yml")).sub("levels:\n", "levels:\n- - workers\n"))
        status, out, = run_cli("scan", @project)
        lines = out.lines(chomp: true)
        assert_equal 0, status
        assert_equal "1 unresolved associations, 1 polymorphic associations (no target)", lines[1]
        assert_match(/\Aunlisted foreign: /, lines[2])
        assert_equal ["warning: levels: unknown folder workers"], lines.drop(3)
      end
```

In `test/smoke_test.rb`, replace `test_a_clean_project_passes_and_prints_counts` with:

```ruby
      def test_a_clean_project_passes_and_prints_counts_and_each_violating_edge
        out = StringIO.new
        project = git_project
        assert_empty Smoke.run([project], out: out)
        assert_match(/\A#{File.basename(project)}: \d+ classes, \d+ violating$/, out.string)
        assert_includes out.string.lines(chomp: true), "  Order -> Reports::Summary (dependency)"
      end
```

and add:

```ruby
      def test_a_wrong_kind_fails_with_the_found_and_the_expected_kind
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"),
                   YAML.dump([{ "from" => "Order", "to" => "User", "kind" => "dependency", "violating" => false }]))
        assert_equal ["#{File.basename(project)}: Order -> User is association, violating false; expected dependency, violating false"],
                     Smoke.run([project], out: StringIO.new)
      end

      def test_two_projects_report_apart
        first = git_project
        second = git_project
        File.write(Workspace.new(second).path("expect.yml"), YAML.dump([{ "from" => "Order", "to" => "Ghost", "kind" => "dependency", "violating" => false }]))
        out = StringIO.new
        failures = Smoke.run([first, second], out: out)
        assert_equal ["#{File.basename(second)}: missing edge Order -> Ghost (dependency)"], failures
        assert_equal 2, out.string.lines.count { |line| line.match?(/: \d+ classes, \d+ violating$/) }
      end

      def test_a_scan_that_raises_still_checks_git_status
        project = git_project
        File.write(Workspace.new(project).path("policy.yml"), "levels: [\n")
        failures = Smoke.run([project], out: StringIO.new) { File.write(File.join(project, "stray.txt"), "x") }
        assert_match(/: policy\.yml line \d+: /, failures.first)
        assert_includes failures, "#{File.basename(project)}: git status changed during the scan"
      end

      def test_a_folder_that_is_not_a_git_repository_fails_with_the_reason
        project = project_copy
        assert_equal ["#{File.basename(project)}: not a git repository, so smoke cannot check that git status stays the same"],
                     Smoke.run([project], out: StringIO.new)
      end

      def test_an_empty_expect_file_passes_and_a_non_list_fails
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"), "")
        assert_empty Smoke.run([project], out: StringIO.new)
        File.write(Workspace.new(project).path("expect.yml"), "from: Order\n")
        assert_equal ["#{File.basename(project)}: expect.yml must be a list of edges"], Smoke.run([project], out: StringIO.new)
      end
```

Note: `test_a_scan_that_raises_still_checks_git_status` uses the block, which runs between the two git checks; in Step 3 the block runs also when the scan raises.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/cli_test.rb -n /association_counts/ && bundle exec ruby -Itest -Ilib test/smoke_test.rb`
Expected: the CLI test fails on line 2 (it is the `unlisted foreign` line); smoke fails on the missing edge lines, the git check after a raise, the non-git message and the empty `expect.yml` (`undefined method 'filter_map' for nil`).

- [ ] **Step 3: Write the code.** In `lib/uml/viewer/cli.rb`, replace `run_scan`:

```ruby
      def run_scan
        Graph.prepare(workspace)
        graph = Graph.build(workspace)
        summary = graph["summary"]
        violating = graph["edges"].count { |edge| edge["violating"] }
        @out.puts "#{graph['classes'].size} classes, #{graph['edges'].size} edges, #{violating} violating, " \
                  "skipped #{summary['skipped'].size} files, no constant"
        @out.puts "#{summary['unresolved']} unresolved associations, #{summary['polymorphic']} polymorphic associations (no target)"
        @out.puts "unlisted foreign: #{summary['foreign'].map { |name, count| "#{name} (#{count})" }.join(', ')}"
        summary["warnings"].each { |warning| @out.puts "warning: #{warning}" }
        0
      end
```

Replace `lib/uml/viewer/smoke.rb` with:

```ruby
require "open3"
require "yaml"

module Uml
  module Viewer
    module Smoke
      def self.run(paths, out:, &between)
        paths.flat_map do |path|
          name = File.basename(path)
          before, repository = git_status(path)
          next ["#{name}: not a git repository, so smoke cannot check that git status stays the same"] unless repository

          failures = check(path, name, out, between)
          failures << "#{name}: git status changed during the scan" unless git_status(path).first == before
          failures
        end
      end

      def self.check(path, name, out, between)
        workspace = Workspace.new(path)
        Graph.prepare(workspace)
        graph = Graph.build(workspace)
        violating = graph["edges"].select { |edge| edge["violating"] }
        out.puts "#{name}: #{graph['classes'].size} classes, #{violating.size} violating"
        violating.each { |edge| out.puts "  #{edge['from']} -> #{edge['to']} (#{edge['kind']})" }
        expectations(workspace, graph).map { |problem| "#{name}: #{problem}" }
      rescue StandardError => error
        ["#{name}: #{error.message}"]
      ensure
        between&.call
      end

      def self.git_status(path)
        text, status = Open3.capture2e("git", "--no-optional-locks", "-C", path, "status", "--porcelain")
        [text, status.success?]
      end

      def self.expectations(workspace, graph)
        file = workspace.path("expect.yml")
        return [] unless File.exist?(file)

        wants = YAML.safe_load(File.read(file))
        return [] if wants.nil?
        return ["expect.yml must be a list of edges"] unless wants.is_a?(Array) && wants.all?(Hash)

        wants.filter_map do |want|
          found = graph["edges"].find { |edge| edge["from"] == want["from"] && edge["to"] == want["to"] }
          if found.nil?
            "missing edge #{want['from']} -> #{want['to']} (#{want['kind']})"
          elsif found["kind"] != want["kind"] || found["violating"] != want["violating"]
            "#{want['from']} -> #{want['to']} is #{found['kind']}, violating #{found['violating']}; " \
              "expected #{want['kind']}, violating #{want['violating']}"
          end
        end
      end
    end
  end
end
```

The Rakefile calls `Smoke.run(paths, out: $stdout)` and needs no change.

- [ ] **Step 4: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/cli_test.rb && bundle exec ruby -Itest -Ilib test/smoke_test.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/uml/viewer/cli.rb lib/uml/viewer/smoke.rb test/cli_test.rb test/smoke_test.rb
git commit -m "feat: print association counts and warnings in scan, and make smoke print red edges and check git after a failed scan"
```

---

### Task 9: Server: the page without a token, /source, /session and source polling

**Files:**
- Modify: `lib/uml/viewer/server.rb`, `lib/uml/viewer/graph.rb`
- Test: `test/server_test.rb`, `test/graph_test.rb`

**Interfaces:**
- Consumes: `graph.json` version 2 (Task 7).
- Produces:
  - `GET /` serves `index.html` without a token.
  - `GET /source?file=<path>&line=<n>` (token) returns `{"file", "line", "text"}` for a file of a class in `graph.json`; 403 `{"error" => "not a scanned file"}` for any other path; 404 `{"error" => "file gone: <path>"}` when the file no longer exists.
  - `GET /session` (token) returns `session.json`, or `{}`. `PUT /session` (token) stores a JSON object with only the keys `drill` (list of strings), `zoom` (number), `scroll` (`{x, y}` numbers) and `proposal` (string or null), and answers 204. Bad JSON, an unknown key or a wrong type gets 400 with the reason; a body over 4 KB gets 413.
  - `Graph.inputs(workspace) -> {path => mtime_float_or_nil}` for `policy.yml` and every `*.rb` under the source roots (the default roots when the policy is invalid). A file that vanishes between the glob and the stat has `nil`.
  - The server rescans when `Graph.inputs` changes. A read error in the poll goes to `/version` `error` as `"cannot watch the project: <reason>"` and the poll goes on. `shutdown` joins the poll thread.

- [ ] **Step 1: Write the failing tests.** In `test/server_test.rb`, add `put: Net::HTTP::Put` to the `klass` map in `request`. Replace `test_the_page_needs_the_token_in_the_query` with:

```ruby
      def test_the_page_needs_no_token_because_it_holds_no_data
        response = request(:get, "/", token: nil)
        assert_equal ["200", "text/html; charset=utf-8"], [response.code, response["Content-Type"]]
        refute_includes response.body, @server.token
      end
```

Add:

```ruby
      def test_source_returns_the_text_of_a_scanned_file_with_the_line
        body = JSON.parse(request(:get, "/source?file=app/models/order.rb&line=7").body)
        assert_equal ["app/models/order.rb", 7], body.values_at("file", "line")
        assert_includes body["text"], "def total = Order.sum(:amount)"
      end

      def test_source_refuses_a_path_outside_the_graph
        ["../../etc/passwd", "Gemfile", "app/views/orders/index.html.erb", "lib/scripts/run_once.rb"].each do |path|
          response = request(:get, "/source?file=#{path}&line=1")
          assert_equal ["403", "not a scanned file"], [response.code, JSON.parse(response.body)["error"]], path
        end
      end

      def test_source_needs_the_token
        assert_equal "403", request(:get, "/source?file=app/models/order.rb&line=1", token: nil).code
      end

      def test_source_of_a_file_deleted_since_the_scan_gets_404_with_the_file
        File.delete(File.join(@project, "app/models/user.rb"))
        response = request(:get, "/source?file=app/models/user.rb&line=1")
        assert_equal ["404", "file gone: app/models/user.rb"], [response.code, JSON.parse(response.body)["error"]]
      end

      def test_session_starts_empty_and_returns_what_was_stored_with_mode_0600
        assert_equal({}, JSON.parse(request(:get, "/session").body))
        view = { "drill" => ["root", "Reports"], "zoom" => 1.25, "scroll" => { "x" => 0, "y" => 40 }, "proposal" => nil }
        assert_equal "204", request(:put, "/session", body: JSON.generate(view)).code
        assert_equal view, JSON.parse(request(:get, "/session").body)
        assert_equal 0o600, File.stat(@workspace.path("session.json")).mode & 0o777
      end

      def test_a_bad_session_gets_400_with_the_reason
        assert_equal "unknown key: theme", JSON.parse(request(:put, "/session", body: '{"theme":"dark"}').body)["error"]
        assert_equal "drill must be a list of ids", JSON.parse(request(:put, "/session", body: '{"drill":"root"}').body)["error"]
        assert_equal "zoom must be a number", JSON.parse(request(:put, "/session", body: '{"zoom":"big"}').body)["error"]
        assert_equal "scroll must hold x and y numbers", JSON.parse(request(:put, "/session", body: '{"scroll":{"x":1}}').body)["error"]
        assert_equal "session must be a JSON object", JSON.parse(request(:put, "/session", body: "[1]").body)["error"]
        assert_equal ["400", "body is not JSON"], request(:put, "/session", body: "{").then { |r| [r.code, JSON.parse(r.body)["error"]] }
        assert_equal "413", request(:put, "/session", body: JSON.generate("drill" => ["x" * 5000])).code
      end

      def test_a_new_source_file_rescans_and_a_deleted_one_leaves_the_graph
        path = File.join(@project, "app/models/invoice.rb")
        File.write(path, "class Invoice\nend\n")
        wait_for_graph("the new Invoice class never reached the graph") { |graph| graph["classes"].any? { |entry| entry["id"] == "Invoice" } }
        File.delete(path)
        wait_for_graph("the deleted Invoice class stayed in the graph") { |graph| graph["classes"].none? { |entry| entry["id"] == "Invoice" } }
      end

      def test_an_unreadable_policy_shows_in_version_and_the_poll_goes_on
        File.chmod(0o000, @workspace.path("policy.yml"))
        Timeout.timeout(5, Timeout::Error, "/version never reported the watch error") do
          sleep 0.1 until JSON.parse(request(:get, "/version").body)["error"].to_s.start_with?("cannot watch the project: ")
        end
        File.chmod(0o600, @workspace.path("policy.yml"))
        File.write(File.join(@project, "app/models/invoice.rb"), "class Invoice\nend\n")
        wait_for_graph("the poll stopped after the read error") { |graph| graph["classes"].any? { |entry| entry["id"] == "Invoice" } }
      ensure
        File.chmod(0o600, @workspace.path("policy.yml"))
      end

      def wait_for_graph(message)
        Timeout.timeout(5, Timeout::Error, message) do
          sleep 0.1 until yield(JSON.parse(request(:get, "/graph.json").body))
        end
      end
```

Add to `test/graph_test.rb`:

```ruby
      def test_inputs_list_the_policy_and_every_source_file_and_survive_a_dangling_symlink
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        File.symlink(File.join(project, "app/models/missing.rb"), File.join(project, "app/models/ghost.rb"))
        inputs = Graph.inputs(workspace)
        assert_includes inputs.keys, workspace.path("policy.yml")
        assert_kind_of Float, inputs[File.join(project, "app/models/order.rb")]
        assert_nil inputs[File.join(project, "app/models/ghost.rb")]
      end

      def test_inputs_fall_back_to_the_default_sources_when_the_policy_is_invalid
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        workspace.write_atomic("policy.yml", "levels: [\n")
        assert_includes Graph.inputs(workspace).keys, File.join(project, "app/models/order.rb")
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/server_test.rb && bundle exec ruby -Itest -Ilib test/graph_test.rb -n /inputs/`
Expected: the page test gets 403; `/source` and `/session` get 404 `not found`; the new-file test times out; the watch-error test times out; `Graph.inputs` is undefined.

- [ ] **Step 3: Add `Graph.inputs`.** In `lib/uml/viewer/graph.rb`:

```ruby
      def self.inputs(workspace)
        sources = begin
          PolicyFile.load(workspace.path("policy.yml"))["sources"]
        rescue PolicyFile::Invalid
          PolicyFile::DEFAULTS["sources"]
        end
        files = sources.flat_map { |source| Dir.glob("#{source}/**/*.rb", base: workspace.root) }
        ([workspace.path("policy.yml")] + files.map { |file| File.join(workspace.root, file) }).to_h { |path| [path, mtime(path)] }
      end

      def self.mtime(path)
        File.mtime(path).to_f
      rescue Errno::ENOENT
        nil
      end
```

- [ ] **Step 4: Change the server.** In `lib/uml/viewer/server.rb`:

  1. In `route`, change `return page(req, res) if req.request_method == "GET" && req.path == "/"` to `return page(res) if req.request_method == "GET" && req.path == "/"`, and replace `page`:

```ruby
      def page(res)
        res.status = 200
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = File.read(File.join(WEB, "index.html"))
      end
```

  2. Add routes to the `case` after `/version`:

```ruby
        when ["GET", "/source"] then source(req, res)
        when ["GET", "/session"] then raw(res, 200, File.exist?(@workspace.path("session.json")) ? File.read(@workspace.path("session.json")) : "{}")
        when ["PUT", "/session"] then save_session(req, res)
```

  3. Add:

```ruby
      SESSION_KEYS = %w[drill zoom scroll proposal].freeze

      def source(req, res)
        file = req.query["file"].to_s
        return respond(res, 403, "error" => "not a scanned file") unless scanned_files.include?(file)

        text = File.read(File.join(@workspace.root, file), encoding: "UTF-8").scrub
        respond(res, 200, "file" => file, "line" => req.query["line"].to_i, "text" => text)
      rescue Errno::ENOENT
        respond(res, 404, "error" => "file gone: #{file}")
      end

      def scanned_files
        JSON.parse(File.read(@workspace.path("graph.json")))["classes"].flat_map { |entry| entry["files"] }.to_set
      end

      def save_session(req, res)
        return respond(res, 413, "error" => "too large") if req["Content-Length"].to_i > MAX_BODY

        text = read_capped(req)
        return respond(res, 413, "error" => "too large") if text.bytesize > MAX_BODY

        body = JSON.parse(text)
        reason = session_problem(body)
        return respond(res, 400, "error" => reason) if reason

        @workspace.write_atomic("session.json", JSON.generate(body))
        res.status = 204
      rescue JSON::ParserError
        respond(res, 400, "error" => "body is not JSON")
      end

      def session_problem(body)
        return "session must be a JSON object" unless body.is_a?(Hash)

        extra = (body.keys - SESSION_KEYS).first
        return "unknown key: #{extra}" if extra
        return "drill must be a list of ids" unless body["drill"].nil? || (body["drill"].is_a?(Array) && body["drill"].all?(String))
        return "zoom must be a number" unless body["zoom"].nil? || body["zoom"].is_a?(Numeric)
        unless body["scroll"].nil? || (body["scroll"].is_a?(Hash) && body["scroll"].keys.sort == %w[x y] && body["scroll"].values.all?(Numeric))
          return "scroll must hold x and y numbers"
        end
        return "proposal must be an id or null" unless body["proposal"].nil? || body["proposal"].is_a?(String)

        nil
      end
```

Move `SESSION_KEYS` up next to `MAX_BODY` with the other constants.

  4. Replace the policy poll with an input poll. In `start`, change `Thread.new { watch_policy }` to `@watcher = Thread.new { watch_inputs }`. In `shutdown`, after `@stopping = true`, add `@watcher&.join(@poll + 1)`. Replace `watch_policy` and `policy_mtime` with:

```ruby
      def watch_inputs
        last = Graph.inputs(@workspace)
        until @stopping
          sleep @poll
          current = read_inputs
          next if current.nil? || current == last

          last = current
          @rescanner.trigger
        end
      end

      def read_inputs
        inputs = Graph.inputs(@workspace)
        @watch_error = nil
        inputs
      rescue SystemCallError => error
        @watch_error = "cannot watch the project: #{error.message}"
        nil
      end
```

  5. In `version`, change `"error" => @rescanner.error` to `"error" => @watch_error || @rescanner.error`.
  6. Add `require "set"` at the top of the file.

The first `Graph.inputs` call in `watch_inputs` can also raise. Wrap it: `last = read_inputs || {}`.

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/server_test.rb && bundle exec ruby -Itest -Ilib test/graph_test.rb`
Expected: all pass.

Run: `bundle exec rake test`
Expected: all pass. The browser tests still open the page with `?token=`.

- [ ] **Step 6: Check that the tests can tell.** In `source`, change `scanned_files.include?(file)` to `true`. Run `test/server_test.rb -n /source_refuses/`. Expected: it fails on `../../etc/passwd`. Restore it.

- [ ] **Step 7: Commit**

```bash
git add lib/uml/viewer/server.rb lib/uml/viewer/graph.rb test/server_test.rb test/graph_test.rb
git commit -m "feat: serve source slices and the stored view, serve the page without a token, and rescan on any source change"
```

---

### Task 10: The page: drill-down, crumbs, zoom, session and reload

**Files:**
- Modify: `lib/uml/viewer/web/index.html`, `lib/uml/viewer/web/app.js`
- Test: `test/browser_test.rb`

**Interfaces:**
- Consumes: `graph.views` (Task 7); `GET /session`, `PUT /session`, the page without a token (Task 9).
- Produces (DOM contract for Task 11 and the tests):
  - Each node is `g.box` with `data-id`, `data-type` (`namespace`, `folder`, `class` or `foreign`) and the class `box <type>`. A foreign node draws an `ellipse`, the others a `rect`.
  - Member lines are `text.member` with `data-id` and `data-kind` (`namespace` or `class`).
  - `#crumbs` holds one `button.crumb` per open view, with `data-id`; the root crumb shows the graph title.
  - Double-click on a namespace or folder box, or on a namespace member line, opens that view. `Escape` goes up one view. `Ctrl` (or `Cmd`) with `=`/`+`, `-`, `0` zooms in, out, and resets.
  - The page saves `{drill, zoom, scroll}` with `PUT /session` at most once per second, and restores it on load.
  - Functions Task 11 extends: `drawArrow(edge, arrow, index)`, `openMenu(x, y)`, `onKey(event)`, `onDoubleClick(event)`.

- [ ] **Step 1: Write the failing tests.** Add to `test/browser_test.rb` (helpers first, in the helper section):

```ruby
      def press(key, ctrl: false)
        @browser.evaluate(%(document.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, ctrlKey: #{ctrl} }))))
      end

      def double_click(css)
        wait_for(css).click(mode: :double)
      end

      def crumbs
        @browser.css("#crumbs button.crumb").map(&:text)
      end

      def box_y(id)
        @browser.at_css(%(g.box[data-id="#{id}"]))["transform"][/translate\([\d.]+,([\d.]+)\)/, 1].to_f
      end
```

```ruby
      def test_double_click_on_a_namespace_box_opens_its_view_and_escape_goes_back
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
        press("Escape")
        wait_for('g.box[data-id="folder:models"]')
        assert_equal ["rails_shapes"], crumbs
      end

      def test_double_click_on_a_namespace_member_opens_that_view_with_its_parents_in_the_crumbs
        boot_nested_namespace_project
        @browser.goto(@server.url)
        double_click('text.member[data-id="Shop::Billing"]')
        wait_for('g.box.class[data-id="Shop::Billing::Invoice"]')
        assert_equal ["extra", "Shop", "Billing"], crumbs
        press("Escape")
        wait_for('g.box.namespace[data-id="Shop::Billing"]')
      end

      def test_a_crumb_opens_its_view
        boot_nested_namespace_project
        @browser.goto(@server.url)
        double_click('text.member[data-id="Shop::Billing"]')
        wait_for('g.box.class[data-id="Shop::Billing::Invoice"]')
        @browser.at_css('#crumbs button.crumb[data-id="root"]').click
        wait_for('g.box.namespace[data-id="Shop"]')
      end

      def test_the_open_view_survives_a_graph_change
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        File.write(File.join(@workspace.root, "app/services/reports/late.rb"), "module Reports\n  class Late\n  end\nend\n")
        Graph.build(@workspace)
        wait_for('g.box.class[data-id="Reports::Late"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_reload_without_the_token_in_the_url_draws_the_page_and_restores_the_open_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        wait_for('g.box.class[data-id="Reports::Summary"]')
        wait_until(-> { "session.json never held the open view" }) do
          File.exist?(@workspace.path("session.json")) && JSON.parse(File.read(@workspace.path("session.json")))["drill"] == ["root", "Reports"]
        end
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal "", @browser.at_css("#banner").text
      end

      def test_a_saved_view_that_no_longer_exists_opens_its_nearest_parent
        @workspace.write_atomic("session.json", JSON.generate("drill" => ["root", "Reports", "Reports::Gone"]))
        @browser.goto(@server.url)
        wait_for('g.box.class[data-id="Reports::Summary"]')
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_a_page_without_any_token_says_the_session_expired
        @browser.goto("http://127.0.0.1:#{@server.port}/")
        wait_for_text("#banner", "session expired: reopen with uml-viewer")
      end

      def test_ctrl_plus_zooms_in_and_ctrl_zero_resets
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"]')
        width = @browser.at_css("#diagram")["width"].to_f
        press("=", ctrl: true)
        wait_until(-> { "the diagram did not zoom in" }) { (@browser.at_css("#diagram")["width"].to_f - width * 1.25).abs < 0.5 }
        press("0", ctrl: true)
        wait_until(-> { "the zoom did not reset" }) { (@browser.at_css("#diagram")["width"].to_f - width).abs < 0.5 }
      end

      def test_a_box_without_a_level_sits_above_the_boxes_with_levels
        reboot(build_project("app/models/order.rb" => "class Order\nend\n", "app/workers/sync.rb" => "class Sync\n  def run = Order.first\nend\n"))
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:workers"]')
        assert_operator box_y("folder:workers"), :<, box_y("folder:models")
      end

      def test_a_listed_foreign_name_is_an_oval_on_the_first_screen
        reboot(build_project("app/models/order.rb" => "class Order\n  def dump = JSON.generate({})\nend\n"))
        @workspace.write_atomic("policy.yml", File.read(@workspace.path("policy.yml")).sub(/^foreign:.*$/, "foreign: [JSON]"))
        Graph.build(@workspace)
        @browser.goto(@server.url)
        wait_for('g.box.foreign[data-id="foreign:JSON"] ellipse')
        assert_equal "JSON", @browser.at_css('g.box.foreign[data-id="foreign:JSON"] text.title').text
        assert @browser.at_css("path.arrow")
      end

      def test_a_failed_graph_fetch_says_server_not_reachable
        @browser.network.intercept
        @browser.on(:request) { |request| request.url.include?("/graph.json") ? request.abort : request.continue }
        @browser.goto(@server.url)
        wait_for_text("#banner", "server not reachable")
        refute_includes @browser.at_css("#banner").text, "Failed to fetch"
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: the new tests fail: no `#crumbs`, no `g.box.class`, no zoom, the reload test gets no drawing, the null-level box sits at the bottom, the foreign node has a `rect`, and the failed fetch says `Failed to fetch`.

- [ ] **Step 3: Replace `lib/uml/viewer/web/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>uml-viewer</title>
<style>
  :root { --bg: #f7f7f4; --fg: #1d2021; --box: #ffffff; --line: #6b7075; --red: #c0392b; --muted: #8a8f94; }
  @media (prefers-color-scheme: dark) { :root { --bg: #1b1d1f; --fg: #e6e6e3; --box: #26292c; --line: #9aa0a6; --red: #ff6b5b; --muted: #7b8186; } }
  [hidden] { display: none !important; }
  html, body { margin: 0; height: 100%; background: var(--bg); color: var(--fg); font: 13px/1.3 ui-monospace, Menlo, monospace; }
  #bar { position: fixed; top: 0; left: 0; right: 0; display: flex; gap: 16px; align-items: center; padding: 8px 12px; background: var(--bg); border-bottom: 1px solid var(--line); z-index: 2; }
  #crumbs { display: flex; gap: 4px; }
  button.crumb { font: inherit; font-weight: bold; background: none; color: var(--fg); border: 0; padding: 0; cursor: pointer; }
  button.crumb:disabled { cursor: default; }
  button.crumb + button.crumb::before { content: "› "; color: var(--muted); font-weight: normal; }
  #banner { color: var(--red); }
  #banner:empty { display: none; }
  svg { position: absolute; top: 36px; left: 0; }
  g.box rect, g.box ellipse { fill: var(--box); stroke: var(--line); }
  g.box.foreign ellipse { stroke-dasharray: 4 3; }
  g.box.folder text.title { font-style: italic; }
  text { fill: var(--fg); }
  text.level, text.more { fill: var(--muted); }
  path.arrow { fill: none; stroke: var(--line); stroke-width: 1.2; marker-end: url(#head); }
  path.arrow.violating { stroke: var(--red); marker-end: url(#head-red); }
  #menu { position: fixed; display: none; flex-direction: column; background: var(--box); border: 1px solid var(--line); z-index: 3; }
  #menu.open { display: flex; }
  #menu button { font: inherit; background: none; color: var(--fg); border: 0; padding: 6px 14px; text-align: left; cursor: pointer; }
  #toast { position: fixed; bottom: 12px; left: 12px; color: var(--red); }
</style>
</head>
<body>
<div id="bar"><span id="crumbs"></span><span id="status"></span><span id="banner"></span></div>
<svg id="diagram"></svg>
<div id="menu"><button data-op="explain">Explain</button><button data-op="omit">Omit</button></div>
<div id="toast"></div>
<script src="/elk.js"></script>
<script src="/app.js"></script>
</body>
</html>
```

- [ ] **Step 4: Replace `lib/uml/viewer/web/app.js`**

```js
(() => {
  const params = new URLSearchParams(location.search);
  const token = params.get("token") || sessionStorage.getItem("uml-token");
  if (params.get("token")) {
    sessionStorage.setItem("uml-token", params.get("token"));
    history.replaceState(null, "", location.pathname);
  }
  const svg = document.getElementById("diagram");
  const menu = document.getElementById("menu");
  const banner = document.getElementById("banner");
  const crumbs = document.getElementById("crumbs");
  const NS = "http://www.w3.org/2000/svg";
  const LINE = 16;
  const MAX_MEMBERS = 15;
  const ZOOM_STEP = 1.25;
  let graph = null;
  let graphTime = null;
  let drawError = null;
  let scanError = null;
  let drawing = false;
  let menuTarget = null;
  let drill = ["root"];
  let zoom = 1;
  let size = { width: 0, height: 0 };
  let pendingScroll = null;
  let saveTimer = null;

  const api = (path, options = {}) =>
    fetch(path, { ...options, headers: { "X-UML-Token": token, "Content-Type": "application/json", ...(options.headers || {}) } });

  const el = (name, attrs = {}, parent = svg) => {
    const node = document.createElementNS(NS, name);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
    parent.appendChild(node);
    return node;
  };

  const levelText = (levels) => (levels ? (levels[0] === levels[1] ? `${levels[0]}` : `${levels[0]}..${levels[1]}`) : "");

  const chain = (id) => {
    const ids = [];
    for (let view = graph.views[id]; view; view = graph.views[view.parent]) ids.unshift(view.id);
    return ids;
  };

  const settleDrill = () => {
    const existing = [...drill].reverse().find((id) => graph.views[id]) || "root";
    drill = chain(existing);
  };

  const memberLines = (node) => {
    const members = node.members || [];
    const lines = members.slice(0, MAX_MEMBERS).map((member) => ({ id: member.id, kind: member.type, text: (member.type === "namespace" ? "▸ " : "") + member.label }));
    if (members.length > MAX_MEMBERS) lines.push({ more: true, text: `+${members.length - MAX_MEMBERS} more` });
    return lines;
  };

  const caption = (node) => (node.type === "class" && node.stereotype !== "class" ? `«${node.stereotype}» ` : "") + node.label;

  const sized = (node) => {
    const lines = memberLines(node);
    const title = caption(node);
    const width = 24 + 7.4 * Math.max(title.length + 6, ...lines.map((line) => line.text.length));
    return { node, lines, title, width, height: 30 + LINE * lines.length };
  };

  const showBanner = () => {
    banner.textContent = drawError || (scanError ? `${scanError}; showing last good graph` : "");
  };

  const expired = () => {
    banner.textContent = "session expired: reopen with uml-viewer";
  };

  const applyZoom = () => {
    svg.setAttribute("viewBox", `0 0 ${size.width} ${size.height}`);
    svg.setAttribute("width", size.width * zoom);
    svg.setAttribute("height", size.height * zoom);
  };

  const saveSession = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      api("/session", { method: "PUT", body: JSON.stringify({ drill, zoom, scroll: { x: scrollX, y: scrollY } }) }).catch(() => {});
    }, 1000);
  };

  const renderCrumbs = () => {
    crumbs.replaceChildren(...drill.map((id, index) => {
      const crumb = document.createElement("button");
      crumb.className = "crumb";
      crumb.dataset.id = id;
      crumb.textContent = id === "root" ? graph.title : graph.views[id].label;
      crumb.disabled = index === drill.length - 1;
      return crumb;
    }));
  };

  const drawNode = (placed, { node, lines, title }) => {
    const group = el("g", { class: `box ${node.type}`, "data-id": node.id, "data-type": node.type, transform: `translate(${placed.x + 20},${placed.y + 20})` });
    if (node.type === "foreign") {
      el("ellipse", { cx: placed.width / 2, cy: placed.height / 2, rx: placed.width / 2, ry: placed.height / 2 }, group);
      el("text", { class: "title", x: placed.width / 2, y: placed.height / 2 + 4, "text-anchor": "middle" }, group).textContent = title;
      return;
    }
    el("rect", { width: placed.width, height: placed.height, rx: 4 }, group);
    el("text", { class: "title", x: 10, y: 18 }, group).textContent = title;
    el("text", { class: "level", x: placed.width - 10, y: 18, "text-anchor": "end" }, group).textContent = levelText(node.levels);
    lines.forEach((line, index) => {
      const attrs = { x: 14, y: 36 + LINE * index, class: line.more ? "more" : "member" };
      if (!line.more) Object.assign(attrs, { "data-id": line.id, "data-kind": line.kind });
      el("text", attrs, group).textContent = line.text;
    });
  };

  function drawArrow(edge, arrow) {
    (edge.sections || []).forEach((section) => {
      const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint];
      const d = points.map((point, i) => `${i ? "L" : "M"}${point.x + 20},${point.y + 20}`).join(" ");
      const path = el("path", { class: `arrow${arrow.violating ? " violating" : ""}`, d });
      el("title", {}, path).textContent = arrow.pairs.map((pair) => `${pair.from} -> ${pair.to} (${pair.kind})`).join("\n");
    });
  }

  async function draw() {
    settleDrill();
    renderCrumbs();
    const view = graph.views[drill[drill.length - 1]];
    const nodes = view.nodes.map(sized);
    const top = Math.max(0, ...view.nodes.flatMap((node) => node.levels || [])) + 1;
    const layout = await new ELK().layout({
      id: "root",
      layoutOptions: {
        "elk.algorithm": "layered", "elk.direction": "UP", "elk.edgeRouting": "ORTHOGONAL",
        "elk.partitioning.activate": "true", "elk.spacing.nodeNode": "40", "elk.layered.spacing.nodeNodeBetweenLayers": "60"
      },
      children: nodes.map(({ node, width, height }) => ({
        id: node.id, width, height,
        layoutOptions: { "elk.partitioning.partition": String(node.levels ? node.levels[0] : top) }
      })),
      edges: view.arrows.map((arrow, index) => ({ id: `a${index}`, sources: [arrow.from], targets: [arrow.to] }))
    });
    svg.replaceChildren();
    const defs = el("defs");
    [["head", "var(--line)"], ["head-red", "var(--red)"]].forEach(([id, color]) => {
      const marker = el("marker", { id, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto" }, defs);
      el("path", { d: "M0,0 L10,5 L0,10 z", fill: color }, marker);
    });
    size = { width: layout.width + 40, height: layout.height + 40 };
    applyZoom();
    const byId = Object.fromEntries(nodes.map((entry) => [entry.node.id, entry]));
    layout.children.forEach((placed) => drawNode(placed, byId[placed.id]));
    (layout.edges || []).forEach((edge, index) => drawArrow(edge, view.arrows[index], index));
    if (pendingScroll) {
      scrollTo(pendingScroll.x, pendingScroll.y);
      pendingScroll = null;
    }
  }

  async function render() {
    if (drawing) return;
    drawing = true;
    try {
      await draw();
      drawError = null;
    } catch (error) {
      drawError = `could not draw the graph: ${error.message}`;
    } finally {
      drawing = false;
    }
    showBanner();
  }

  async function loadGraph() {
    const response = await api("/graph.json");
    if (response.status === 403) {
      expired();
      return false;
    }
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    graph = await response.json();
    return true;
  }

  const showStatus = (version) => {
    const alive = version.agent && Date.now() / 1000 - version.agent < 10;
    const failed = version.failed ? ` · command ${version.failed.id} failed: ${version.failed.reason}` : "";
    document.getElementById("status").textContent =
      (alive ? `watcher running (${version.queue} waiting)` : `no agent: ${version.queue} commands wait in the queue`) + failed;
  };

  async function poll() {
    let version;
    try {
      const response = await api("/version");
      if (response.status === 403) return expired();
      version = await response.json();
    } catch (error) {
      banner.textContent = "server not reachable";
      return;
    }
    showStatus(version);
    scanError = version.error;
    if (version.graph !== graphTime && !drawing) {
      try {
        if (!(await loadGraph())) return;
        graphTime = version.graph;
        await render();
      } catch (error) {
        drawError = error instanceof TypeError ? "server not reachable" : `could not draw the graph: ${error.message}`;
      }
    }
    showBanner();
  }

  const openView = (id) => {
    if (!graph || !graph.views[id] || drawing) return;
    drill = chain(id);
    render();
    saveSession();
  };

  function toast(text) {
    const node = document.getElementById("toast");
    node.textContent = text;
    setTimeout(() => { if (node.textContent === text) node.textContent = ""; }, 4000);
  }

  function openMenu(x, y) {
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;
    menu.classList.add("open");
  }

  function onKey(event) {
    if (event.key === "Escape" && drill.length > 1) {
      openView(drill[drill.length - 2]);
      return;
    }
    if ((event.ctrlKey || event.metaKey) && ["=", "+", "-", "0"].includes(event.key)) {
      event.preventDefault();
      zoom = event.key === "0" ? 1 : event.key === "-" ? zoom / ZOOM_STEP : zoom * ZOOM_STEP;
      applyZoom();
      saveSession();
    }
  }

  function onDoubleClick(event) {
    const member = event.target.closest("text.member");
    const box = event.target.closest("g.box");
    if (member && member.dataset.kind === "namespace") return openView(member.dataset.id);
    if (!member && box && ["namespace", "folder"].includes(box.dataset.type)) return openView(box.dataset.id);
  }

  svg.addEventListener("dblclick", (event) => onDoubleClick(event));
  document.addEventListener("keydown", (event) => onKey(event));
  crumbs.addEventListener("click", (event) => {
    const crumb = event.target.closest("button.crumb");
    if (crumb && !crumb.disabled) openView(crumb.dataset.id);
  });
  addEventListener("scroll", saveSession);

  svg.addEventListener("contextmenu", (event) => {
    const member = event.target.closest("text.member");
    const box = event.target.closest("g.box");
    if (!member && (!box || box.dataset.type === "foreign")) return;
    event.preventDefault();
    const type = member ? member.dataset.kind : box.dataset.type;
    menuTarget = { id: member ? member.dataset.id : box.dataset.id, kind: type === "class" ? "class" : "box", proposal_id: null };
    openMenu(event.clientX, event.clientY);
  });

  menu.addEventListener("click", async (event) => {
    const op = event.target.dataset.op;
    menu.classList.remove("open");
    if (!op || !menuTarget) return;
    let response;
    try {
      response = await api("/commands", { method: "POST", body: JSON.stringify({ op, target: menuTarget }) });
    } catch (error) {
      return toast("command not sent: server not reachable");
    }
    if (response.status !== 201) {
      const body = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
      toast(response.status === 429 ? body.error : `command not sent: ${body.error}`);
    }
  });

  document.addEventListener("click", (event) => { if (!menu.contains(event.target)) menu.classList.remove("open"); });

  const restore = (session) => {
    if (Array.isArray(session.drill) && session.drill.length) drill = session.drill;
    if (typeof session.zoom === "number" && session.zoom > 0) zoom = session.zoom;
    if (session.scroll) pendingScroll = session.scroll;
  };

  async function start() {
    if (!token) return expired();
    try {
      const response = await api("/session");
      if (response.ok) restore(await response.json());
    } catch (error) {
      banner.textContent = "server not reachable";
    }
    poll();
    setInterval(poll, 1000);
  }

  start();
})();
```

The `catch(() => {})` on the session save is deliberate: a lost view is no data loss, and the next poll shows "server not reachable" when the server is gone.

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: all pass, the milestone 1 browser tests included.

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/web/index.html lib/uml/viewer/web/app.js test/browser_test.rb
git commit -m "feat: drill into boxes with crumbs and Escape, zoom with Ctrl, and keep the view across reloads and restarts"
```

---

### Task 11: The page: class card, source panel, hover popup, Regen and the menu edge

**Files:**
- Modify: `lib/uml/viewer/web/index.html`, `lib/uml/viewer/web/app.js`
- Test: `test/browser_test.rb`

**Interfaces:**
- Consumes: the DOM contract and functions of Task 10; `graph.classes[].ops` (Task 3); `GET /source` (Task 9).
- Produces:
  - Double-click on a class member line or a class node opens `#card`: the id, `«stereotype» · <kind folder> · level N` (or `no level`), one `p.file` per file, a `p.error` per parse error under `h3.error`, one `li.op` per op (`+` public, `-` private, `#` protected, then the name and `cc N`, with `data-file` and `data-line`), and the note "static scan: dynamic references (constantize, send) are not seen".
  - A click on `li.op` opens `#source` with the header `<file>:<line>` and one `div.line` per line; the line of the op has the class `current` and scrolls into view. A refused file shows the server reason.
  - Hovering an arrow shows `#popup` with one `div.pair` per pair (`<from> -> <to> (<kind>)`), class `violating` on violating pairs. Each arrow has an invisible `path.hit` (10 px wide) on top of the visible path.
  - `#regen` posts `/scans`; a failure shows a toast.
  - The context menu stays inside the window.
  - `Escape` closes the source panel first, then the card, then goes up one view.

- [ ] **Step 1: Write the failing tests.** Add to `test/browser_test.rb`:

```ruby
      def op_texts
        @browser.css("#card li.op").map(&:text)
      end

      def test_double_click_on_a_class_opens_its_card_with_ops_level_and_files
        @browser.goto(@server.url)
        double_click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "«class» · models · level 0"
        assert_equal ["app/models/order.rb"], @browser.css("#card p.file").map(&:text)
        assert_includes op_texts, "+ total  cc 1"
        assert_includes @browser.at_css("#card").text, "static scan: dynamic references (constantize, send) are not seen"
      end

      def test_the_card_shows_each_visibility_sign
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        double_click('g.box.class[data-id="Reports::Exporter"] text.title')
        wait_for_text("#card h2", "Reports::Exporter")
        ["+ self.build  cc 1", "- self.secret  cc 1", "+ run  cc 2", "# rows  cc 1", "- format  cc 1"].each do |text|
          assert_includes op_texts, text
        end
      end

      def test_the_card_of_a_broken_file_shows_its_parse_errors
        @browser.goto(@server.url)
        double_click('text.member[data-id="Broken"]')
        wait_for("#card h3.error")
        assert_match(/\Aline \d+: /, @browser.at_css("#card p.error").text)
      end

      def test_a_click_on_an_op_opens_the_source_at_its_line
        @browser.goto(@server.url)
        double_click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        @browser.css("#card li.op").find { |op| op.text.start_with?("+ total") }.click
        wait_for_text("#source h2", "app/models/order.rb:7")
        assert_includes @browser.at_css("#source .line.current").text, "def total = Order.sum(:amount)"
      end

      def test_a_refused_source_file_shows_the_reason_in_the_panel
        @browser.goto(@server.url)
        double_click('text.member[data-id="Order"]')
        wait_for("#card li.op")
        @browser.evaluate('document.querySelector("#card li.op").dataset.file = "Gemfile"')
        @browser.at_css("#card li.op").click
        wait_for_text("#source", "not a scanned file")
      end

      def test_a_class_that_left_the_graph_shows_a_toast_instead_of_a_card
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        @browser.evaluate('document.querySelector(\'text.member[data-id="Order"]\').dataset.id = "Gone"')
        double_click('text.member[data-id="Gone"]')
        wait_for_text("#toast", "class Gone is not in the graph")
      end

      def test_escape_closes_the_card_before_it_leaves_the_view
        @browser.goto(@server.url)
        double_click('g.box[data-id="Reports"] text.title')
        double_click('g.box.class[data-id="Reports::Summary"] text.title')
        wait_for_text("#card h2", "Reports::Summary")
        press("Escape")
        wait_until(-> { "the card stayed open" }) { @browser.at_css("#card")["hidden"] }
        assert_equal ["rails_shapes", "Reports"], crumbs
      end

      def test_hovering_a_red_arrow_lists_its_pairs_with_the_red_ones_marked
        @browser.goto(@server.url)
        wait_for("path.hit.violating")
        @browser.evaluate('document.querySelector("path.hit.violating").dispatchEvent(new MouseEvent("mouseover", { bubbles: true, clientX: 100, clientY: 100 }))')
        wait_for("#popup .pair.violating")
        assert_includes @browser.css("#popup .pair.violating").map(&:text), "Order -> Pricing (dependency)"
      end

      def test_regen_rescans
        @browser.goto(@server.url)
        wait_for("#regen")
        before = File.mtime(@workspace.path("graph.json"))
        sleep 1.1
        @browser.at_css("#regen").click
        wait_until(-> { "Regen never rewrote graph.json" }) { File.mtime(@workspace.path("graph.json")) > before }
      end

      def test_regen_with_the_server_gone_shows_a_toast
        @browser.goto(@server.url)
        wait_for("#regen")
        shutdown_server
        @browser.at_css("#regen").click
        wait_for_text("#toast", "rescan not started: server not reachable")
      end

      def test_the_context_menu_stays_inside_the_window
        @browser.goto(@server.url)
        wait_for('text.member[data-id="Order"]')
        @browser.evaluate(<<~JS)
          document.querySelector('text.member[data-id="Order"]').dispatchEvent(
            new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: innerWidth - 2, clientY: innerHeight - 2 }))
        JS
        wait_for("#menu.open")
        assert @browser.evaluate('(() => { const r = document.getElementById("menu").getBoundingClientRect(); return r.right <= innerWidth && r.bottom <= innerHeight; })()')
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: the new tests fail: no `#card`, no `#source`, no `path.hit`, no `#regen`, and the menu opens past the window edge.

- [ ] **Step 3: Add the markup.** In `lib/uml/viewer/web/index.html`:

  1. Add to `:root` the token `--hl: #fff3c4;` and to the dark `:root` the token `--hl: #4a4020;`.
  2. Add these rules before `</style>`:

```css
  #regen { font: inherit; background: none; color: var(--fg); border: 1px solid var(--line); border-radius: 3px; padding: 2px 8px; cursor: pointer; }
  aside { position: fixed; top: 36px; bottom: 0; overflow: auto; background: var(--box); border-left: 1px solid var(--line); padding: 8px 12px; z-index: 2; }
  aside h2 { font-size: 14px; margin: 4px 0 8px; }
  #card { right: 0; width: 360px; }
  #source { right: 385px; width: min(720px, 50vw); }
  #card .error { color: var(--red); }
  #card .note, #card .file { color: var(--muted); }
  #card ul { padding: 0; }
  li.op { list-style: none; cursor: pointer; white-space: pre; }
  li.op:hover { text-decoration: underline; }
  #source pre { margin: 0; }
  .line { white-space: pre; }
  .line.current { background: var(--hl); }
  #popup { position: fixed; background: var(--box); border: 1px solid var(--line); padding: 6px 8px; z-index: 3; pointer-events: none; }
  #popup .violating { color: var(--red); }
  path.hit { fill: none; stroke: transparent; stroke-width: 10; }
```

  3. Change the bar to `<div id="bar"><span id="crumbs"></span><button id="regen">Regen</button><span id="status"></span><span id="banner"></span></div>`.
  4. After `<div id="toast"></div>`, add:

```html
<aside id="card" hidden></aside>
<aside id="source" hidden></aside>
<div id="popup" hidden></div>
```

- [ ] **Step 4: Add the behavior.** In `lib/uml/viewer/web/app.js`:

  1. Add `const popup = document.getElementById("popup");` and `let currentArrows = [];` next to the other declarations.
  2. In `draw`, after `const view = ...`, add `currentArrows = view.arrows;`.
  3. Replace `drawArrow`:

```js
  function drawArrow(edge, arrow, index) {
    (edge.sections || []).forEach((section) => {
      const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint];
      const d = points.map((point, i) => `${i ? "L" : "M"}${point.x + 20},${point.y + 20}`).join(" ");
      el("path", { class: `arrow${arrow.violating ? " violating" : ""}`, d });
      el("path", { class: `hit${arrow.violating ? " violating" : ""}`, d, "data-index": index });
    });
  }
```

  4. Replace `openMenu`:

```js
  function openMenu(x, y) {
    menu.classList.add("open");
    const { width, height } = menu.getBoundingClientRect();
    menu.style.left = `${Math.max(0, Math.min(x, innerWidth - width - 4))}px`;
    menu.style.top = `${Math.max(0, Math.min(y, innerHeight - height - 4))}px`;
  }
```

  5. At the start of `onKey`, add:

```js
    if (event.key === "Escape") {
      const source = document.getElementById("source");
      const card = document.getElementById("card");
      if (!source.hidden) {
        source.hidden = true;
        return;
      }
      if (!card.hidden) {
        card.hidden = true;
        return;
      }
    }
```

  6. In `onDoubleClick`, add before the last line:

```js
    if (member && member.dataset.kind === "class") return openCard(member.dataset.id);
    if (!member && box && box.dataset.type === "class") return openCard(box.dataset.id);
```

  7. Add these functions and listeners after `toast`:

```js
  const SIGNS = { public: "+", private: "-", protected: "#" };

  const append = (parent, tag, text, className) => {
    const node = document.createElement(tag);
    node.textContent = text;
    if (className) node.className = className;
    parent.appendChild(node);
    return node;
  };

  function openCard(id) {
    const entry = graph && graph.classes.find((item) => item.id === id);
    if (!entry) return toast(`class ${id} is not in the graph`);
    const card = document.getElementById("card");
    card.replaceChildren();
    append(card, "h2", entry.id);
    const level = entry.level === null || entry.level === undefined ? "no level" : `level ${entry.level}`;
    append(card, "p", `«${entry.stereotype}» · ${entry.kind_folder} · ${level}`);
    entry.files.forEach((file) => append(card, "p", file, "file"));
    if (entry.parse_errors.length) {
      append(card, "h3", "parse errors", "error");
      entry.parse_errors.forEach((error) => append(card, "p", error, "error"));
    }
    const list = append(card, "ul", "");
    entry.ops.forEach((op) => {
      const item = append(list, "li", `${SIGNS[op.visibility]} ${op.name}  cc ${op.cc}`, "op");
      item.dataset.file = op.file;
      item.dataset.line = op.line_start;
    });
    append(card, "p", "static scan: dynamic references (constantize, send) are not seen", "note");
    card.hidden = false;
  }

  async function openSource(file, line) {
    const panel = document.getElementById("source");
    panel.replaceChildren();
    append(panel, "h2", `${file}:${line}`);
    panel.hidden = false;
    let response;
    try {
      response = await api(`/source?file=${encodeURIComponent(file)}&line=${line}`);
    } catch (error) {
      return append(panel, "p", "server not reachable", "error");
    }
    const body = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
    if (!response.ok) return append(panel, "p", body.error, "error");
    const pre = append(panel, "pre", "");
    body.text.split("\n").forEach((text, index) => {
      append(pre, "div", `${String(index + 1).padStart(4)}  ${text}`, index + 1 === line ? "line current" : "line");
    });
    pre.querySelector(".current")?.scrollIntoView({ block: "center" });
  }

  document.getElementById("card").addEventListener("click", (event) => {
    const op = event.target.closest("li.op");
    if (op) openSource(op.dataset.file, Number(op.dataset.line));
  });

  svg.addEventListener("mouseover", (event) => {
    const hit = event.target.closest("path.hit");
    if (!hit) return;
    const arrow = currentArrows[Number(hit.dataset.index)];
    popup.replaceChildren();
    arrow.pairs.forEach((pair) => append(popup, "div", `${pair.from} -> ${pair.to} (${pair.kind})`, pair.violating ? "pair violating" : "pair"));
    popup.style.left = `${event.clientX + 12}px`;
    popup.style.top = `${event.clientY + 12}px`;
    popup.hidden = false;
  });

  svg.addEventListener("mouseout", (event) => {
    if (event.target.closest("path.hit")) popup.hidden = true;
  });

  document.getElementById("regen").addEventListener("click", async () => {
    try {
      const response = await api("/scans", { method: "POST" });
      if (response.status !== 202) toast(`rescan not started: HTTP ${response.status}`);
    } catch (error) {
      toast("rescan not started: server not reachable");
    }
  });
```

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: all pass.

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/web/index.html lib/uml/viewer/web/app.js test/browser_test.rb
git commit -m "feat: open a class card with its ops, a source panel at the op line, and a hover popup that marks red pairs"
```

---

### Task 12: Backlog, README and the real-project check

**Files:**
- Modify: `docs/backlog.md`, `README.md`
- Private, outside the repository: `~/.uml-viewer/projects/<project>/expect.yml` of each test app

**Interfaces:**
- Consumes: everything above.
- Produces: an up-to-date backlog, a README that names the navigation, and a passing smoke run on the three test apps.

This task changes documentation and runs smoke; it adds no code.

- [ ] **Step 1: Remove the fixed items from `docs/backlog.md`.** Delete each line whose item this milestone fixed (the list under "Backlog items folded in" in the scope rulings of this plan). Keep every other line. Change the first heading to `# Backlog after milestone 2`.

- [ ] **Step 2: Describe the navigation in `README.md`.** After the three command lines, add:

```
Double-click a box to open it, Esc to go back. Double-click a class for its card; click an op for its source. Hover an arrow for its pairs. Right-click a box or a class to send Explain or Omit to Claude.
```

- [ ] **Step 3: Check the private expect files.** Before this plan's eng-review, the user confirmed new real edges for each test app: at least one `association` with `class_name:`, one compact-model sibling `association` (legacy app), one red `inheritance` or `implements`, and one `ActiveAdmin(X) -> X` (legacy app). They are in each app's `expect.yml` in its state folder. Never copy them into the repository.

- [ ] **Step 4: Run smoke on the three apps**

Run: `UML_VIEWER_SMOKE=<medium app path>:<large app path>:<legacy app path> bundle exec rake smoke`
Expected: exit 0; one counts line per app followed by its red edges; no failure line. When an edge from milestone 1 changed its kind (for example a `dependency` that is now an `association`), stop and show the user the edge before you change the expect file.

- [ ] **Step 5: Check the repository for private names**

Run the same grep as milestone 1 over the tree and the commit messages of this branch (the app names and their top namespaces, from the user's private list).
Expected: no match.

- [ ] **Step 6: Commit**

```bash
git add docs/backlog.md README.md
git commit -m "docs: remove the backlog items milestone 2 fixed and describe the navigation in the README"
```
