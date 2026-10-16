# uml-viewer milestone 3 (overlay: coverage, CRAP, mutation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Color every box and class by test quality: method coverage from SimpleCov, CRAP per method, a C grade from CRAP, an M grade from an optional mutation snapshot, with grey for "no data" and a card that says why.

**Architecture:** A new `Coverage` unit reads `coverage/.resultset.json` (both SimpleCov formats, several suites) and maps its absolute paths to scanned files. A new pure `Overlay` unit computes method coverage, CRAP, the C and M grades per class, and pooled grades per box. `Graph.build` runs both after the policy, adds a coverage summary, and polls the coverage file and the mutation snapshot as rescan inputs. The page colors boxes by grade, draws a C and an M dot, and shows coverage and CRAP on the card.

**Tech Stack:** Ruby 4.0.6 for development (`.ruby-version`), gem floor Ruby 3.3; prism 1.9; webrick ~> 1.9; json (stdlib); minitest 6; ferrum 0.18 (browser tests only); elkjs 0.12.0 vendored.

**Spec:** `docs/specs/2026-10-14-uml-viewer-design.md`, section 6 (overlay), the overlay rows of section 9 and the overlay tests of section 10. This plan covers milestone 3 of section 11.

**Base:** branch `feat/milestone-3`, stacked on `feat/milestone-2` (not merged yet; the user has not chosen the merge option). Criterion 5b of milestone 1 and the ActiveAdmin pseudo-classes stay open, as recorded in the spec.

## Global Constraints

- Gem name `uml-viewer`; `require "uml/viewer"`; code in `lib/uml/viewer/`; module `Uml::Viewer`.
- Runtime dependencies: `prism` (1.9 or later) and `webrick` (`~> 1.9`). No Rails, no ActiveSupport, no new gem.
- `spec.required_ruby_version = ">= 3.3"`. Develop and test on Ruby 4.0.6.
- Never write a file into a viewed project. The coverage file is read only. All state lives in `~/.uml-viewer/projects/<name>-<hash>/`, or under `UML_VIEWER_HOME` when it is set.
- State folder mode 0700; every state file mode 0600 (`Workspace#write_atomic` does this).
- No code or text copied from `unclebob/uml-viewer`.
- No private project names, class names or paths anywhere in the repository. Real examples appear in tests with changed names and fake paths.
- Strict TDD: write the test, run it, see it fail for the expected reason, then write the code.
- No comments in code. English identifiers. No em dashes in any file.
- Every failure shows the user what went wrong and what to do next, and has a test that asserts the message.
- Commit messages: Conventional Commits, English, no session links or `Claude-Session` trailers.
- Every test sets `UML_VIEWER_HOME` to a temp folder (the test helper does this).
- Do not edit `lib/uml/viewer/web/elk.bundled.js`.

## Real examples (confirmed by the user on 2026-10-16)

From the legacy app's coverage file (one RSpec suite, old array format, inner timestamp 2024-04-25). The tests use these numbers with changed names.

```
#   Rule                         Real case (shape)                                  Right result        Likely wrong rule
--  ----                         -----------------                                  ------------        -----------------
A   method coverage skips the    a 3-line `to_s`: def line hit 1, body line hit 0   coverage 0,         counting the def line
    def line                                                                        CRAP 2.0            gives 0.5, CRAP 1.13
B   CRAP has the cube            a controller action: cc 10, body coverage 8/15     CRAP 20.16          no cube gives 56.67;
                                                                                                        def line gives 18.35
C   class grade = mu + sigma     8 methods with CRAP 20.16, 4.37, 5.0, 2.0, 8.13,   mu 9.21, sigma      a sample sigma or no
    through crap_cutoffs         30.0, 3.01, 1.0 (sigma over all methods, one       9.70, mu + sigma    cube changes the
                                 weight per method)                                 18.91, grade 7      numbers
D   absent file = never loaded   a controller older than the coverage time and      coverage 0, card:   "absent = no data"
                                 not in the resultset                               "not loaded by the  gives grey
                                                                                    tests"
E   stale coverage               39 scanned files changed after the coverage time   grey, card:         old line hits on new
                                                                                    "coverage older     code
                                                                                    than this file"
F   partial-run guard            309 of 316 scanned files in the resultset          no partial banner   fires only below half
```

## Scope rulings for milestone 3

These are rulings, recorded here so a reviewer can reject them.

- **Sigma is the population standard deviation** (divide by n). The spec says "one weight per method" and does not say sample or population. Example C gives grade 7 under both, so it cannot tell; the unit test pins the population form with its own data.
- **Mutation grades per class and per box come from the summed counts** of their methods: `score = killed / (killed + survived + uncovered)` over the sum, `grade = max(1, ceil(score * 10))`. A snapshot key for a method that no longer exists is ignored. The op name `self.x` maps to the key `Class.x`, other ops to `Class#x`.
- **A class node gets the same grade fields as a box:** `c_grade`, `m_grade` and `grade` (the mean of the C and M grades that exist, or null). The page colors class nodes and boxes the same way.
- **An absent file in a partial run** gets no data (grey) and the card note "coverage looks partial: run the full suite". The spec gives the banner, not a card text.
- **An unreadable coverage file** gives grey for every class, the card note "coverage file unreadable: <path>" (not "no coverage", which would send the user to the wrong fix), and the same text as the page banner.
- **An unreadable mutation snapshot** (`mutation.json` in the state folder that is not valid JSON, or not a mapping of mappings) gives the summary warning "mutation snapshot unreadable: <path>" and no M grades. The spec is silent; this follows the coverage rule.
- **Rescans:** the coverage file and the mutation snapshot are inputs of the rescan poll, so a test run or a new snapshot recolors the diagram without a restart. The spec lists only source files and the policy; the user expects a fresh overlay after a test run.
- **Coverage summary:** `graph["summary"]["coverage"]` is `{time, files, scanned, banner}`. `uml-viewer scan` and smoke print one coverage line from it.
- **crap_cutoffs is validated** (backlog item): 9 numbers in rising order.
- **Out of scope:** a mutation tool or writer (spec 12); coverage per branch (the spec uses line coverage only); a legend for the colors (the card states each grade).

## Review Focus

1. A resultset path whose tail matches two scanned files (`/ci/app/models/order.rb` against `app/models/order.rb` and `models/order.rb`). Expected: the longest matching scanned path wins. Test in Task 2.
2. A coverage file read while the test runner still writes it (cut-off JSON). Expected: the graph is still written, every class is grey, the banner says "coverage file unreadable: <path>", and the next poll after the write ends clears it. Tests in Task 2 (unreadable) and Task 4 (banner, then recovery).
3. A method whose line numbers go past the end of its file's hit array (the file grew, but kept an old mtime). Expected: those lines count as not relevant; no exception. Test in Task 3.
4. A class with no ops (a module that holds only constants). Expected: no C grade, no error, and the box grade ignores it. Test in Task 3.
5. A mutation snapshot key for a method that no longer exists, and one for a class method. Expected: the first is ignored, the second matches `Class.x`. Test in Task 3.

## Failure modes of the new paths

```
Failure                                  Handling                                  User sees                                         Test
-------                                  --------                                  ---------                                         ----
no coverage file                         no C grades                               grey C dots; card: "no coverage: run your         overlay_test, browser_test
                                                                                   tests with SimpleCov"
coverage older than a file               that file's coverage not used             grey C dot; card: "coverage older than this       overlay_test
                                                                                   file"
coverage file is not valid JSON or       coverage ignored, graph still written     banner and card: "coverage file unreadable:       coverage_test, graph_test,
has the wrong shape                                                                <path>"                                           browser_test
file absent from the resultset           coverage 0                                red C grade; card: "not loaded by the tests"      overlay_test, browser_test
resultset from a partial run             absent files get no data                  grey C dots; banner: "coverage looks partial:     overlay_test, graph_test
                                                                                   N of M files; run the full suite"
mutation snapshot unreadable             no M grades                               scan: "warning: mutation snapshot unreadable:     graph_test, cli_test
                                                                                   <path>"
crap_cutoffs not 9 rising numbers        scan refuses, keeps the old graph         "policy.yml: crap_cutoffs must be 9 numbers in    policy_file_test
                                                                                   rising order"
```

## File structure

```
Path                                         Change    Responsibility
----                                         ------    --------------
docs/specs/2026-10-14-uml-viewer-design.md   modify    record the rulings above (Task 1)
lib/uml/viewer/coverage.rb                   create    read and parse coverage/.resultset.json
lib/uml/viewer/overlay.rb                    create    pure: method coverage, CRAP, C/M grades, box grades
lib/uml/viewer/graph.rb                      modify    run the overlay, coverage summary, rescan inputs
lib/uml/viewer/policy_file.rb                modify    validate crap_cutoffs
lib/uml/viewer/cli.rb, smoke.rb              modify    print the coverage line
lib/uml/viewer/web/index.html, app.js        modify    grade colors, C and M dots, card metrics, banner
lib/uml/viewer.rb                            modify    require the new units
test/coverage_test.rb, test/overlay_test.rb  create    unit tests on plain data and temp files
test/*_test.rb                               modify    graph, policy_file, cli, smoke, server, browser
docs/backlog.md, README.md                   modify    Task 6
```

---

### Task 1: Record the milestone 3 rulings in the spec

**Files:**
- Modify: `docs/specs/2026-10-14-uml-viewer-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the spec text that the reviewers of Tasks 2 to 6 check against.

Documentation only, so no test. Make each edit with the exact text below.

- [ ] **Step 1: Section 6.2.** After the bullet that starts with "Mutation: an optional snapshot `mutation.json`", insert:

```
- Sigma is the population standard deviation: divide by the number of methods.
- The M grade of a class or a box comes from the summed counts of its methods. The op `self.x` matches the key `Class.x`, other ops `Class#x`. A key for a method that no longer exists is ignored. A snapshot that is not valid JSON, or not a mapping of mappings, gives the scan warning "mutation snapshot unreadable: <path>" and no M grades.
- A class node has the same grades as a box: the C grade, the M grade and their mean.
```

- [ ] **Step 2: Section 6.1.** After the bullet that starts with "**Partial run.**", insert:

```
- **Unreadable file.** A coverage file that is not valid JSON, or has the wrong shape, is ignored: every C dot is grey, and the banner and the card say "coverage file unreadable: <path>". The graph is still written.
- In a partial run, the card of a class with an absent file says "coverage looks partial: run the full suite".
```

- [ ] **Step 3: Section 7.1, rescans.** In the **Rescans** bullet, replace "or when a scanned file or a new `*.rb` file under the source roots changes." with "when a scanned file or a new `*.rb` file under the source roots changes, or when `coverage/.resultset.json` or the state folder's `mutation.json` changes."

- [ ] **Step 4: Section 9.** Insert these rows into the failure table, directly below the row "resultset from a partial run", keeping the column alignment of the table:

```
mutation snapshot unreadable             no M grades                                scan summary warning: "mutation snapshot         graph_test: broken snapshot
                                                                                    unreadable: <path>"
crap_cutoffs not 9 rising numbers        scan refuses, keeps the old graph          "policy.yml: crap_cutoffs must be 9 numbers in   policy_file_test
                                                                                    rising order"
```

- [ ] **Step 5: Check and commit**

Run: `grep -c "$(printf '\xe2\x80\x94')" docs/specs/2026-10-14-uml-viewer-design.md` (counts em dashes)
Expected: `0`

```bash
git add docs/specs/2026-10-14-uml-viewer-design.md
git commit -m "docs(spec): record the milestone 3 rulings for sigma, mutation grades, unreadable files and rescans"
```

---

### Task 2: Coverage

**Files:**
- Create: `lib/uml/viewer/coverage.rb`
- Modify: `lib/uml/viewer.rb`
- Test: `test/coverage_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Uml::Viewer::Coverage.load(root, scanned_files) -> nil | {"time" => Integer|nil, "lines" => {relative_file => [Integer|nil]}}`. `nil` when `<root>/coverage/.resultset.json` does not exist.
  - Raises `Uml::Viewer::Coverage::Unreadable` with the message `"coverage file unreadable: <absolute path>"` when the file is not valid JSON, cannot be read, or has the wrong shape (not a mapping of suites that each hold a `"coverage"` mapping).
  - `Coverage.parse(resultset, scanned_files)` does the same on parsed data: `time` is the newest suite `"timestamp"`; the hits of every suite are added line by line (nil plus nil stays nil; nil counts as 0 next to a number); each absolute path maps to the longest scanned file it ends with (`"/#{file}"`), and a path that matches no scanned file is dropped.

- [ ] **Step 1: Write the failing test.** `test/coverage_test.rb`:

```ruby
require "test_helper"

module Uml
  module Viewer
    class CoverageTest < TestCase
      FILES = ["app/models/order.rb", "app/services/pricing.rb"].freeze

      def root_with(json)
        root = Dir.mktmpdir("uml-viewer-project")
        @project_parents << root
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", ".resultset.json"), json)
        root
      end

      def test_the_old_format_of_one_suite_maps_absolute_paths_to_scanned_files
        resultset = { "RSpec" => { "coverage" => {
          "/home/ci/build/app/models/order.rb" => [1, 0, nil],
          "/home/ci/build/vendor/gems/tool/lib/tool.rb" => [1]
        }, "timestamp" => 1_714_042_370 } }
        assert_equal({ "time" => 1_714_042_370, "lines" => { "app/models/order.rb" => [1, 0, nil] } }, Coverage.parse(resultset, FILES))
      end

      def test_the_new_format_reads_the_lines_key
        resultset = { "Minitest" => { "coverage" => { "/srv/app/services/pricing.rb" => { "lines" => [nil, 2, 0], "branches" => {} } }, "timestamp" => 10 } }
        assert_equal({ "app/services/pricing.rb" => [nil, 2, 0] }, Coverage.parse(resultset, FILES)["lines"])
      end

      def test_two_suites_add_their_hits_and_the_newest_timestamp_is_the_time
        resultset = {
          "RSpec" => { "coverage" => { "/a/app/models/order.rb" => [1, 0, nil, nil] }, "timestamp" => 100 },
          "Minitest" => { "coverage" => { "/b/app/models/order.rb" => { "lines" => [2, 0, 3, nil] } }, "timestamp" => 200 }
        }
        assert_equal({ "time" => 200, "lines" => { "app/models/order.rb" => [3, 0, 3, nil] } }, Coverage.parse(resultset, FILES))
      end

      def test_the_longest_matching_scanned_path_wins
        files = ["models/order.rb", "app/models/order.rb"]
        resultset = { "RSpec" => { "coverage" => { "/ci/app/models/order.rb" => [1] }, "timestamp" => 1 } }
        assert_equal ["app/models/order.rb"], Coverage.parse(resultset, files)["lines"].keys
      end

      def test_a_missing_file_gives_nil
        assert_nil Coverage.load(Dir.mktmpdir.tap { |dir| @project_parents << dir }, FILES)
      end

      def test_load_reads_the_inner_timestamp_so_a_touch_of_the_file_changes_nothing
        root = root_with(JSON.generate("RSpec" => { "coverage" => { "/x/app/models/order.rb" => [1] }, "timestamp" => 1_000 }))
        File.utime(Time.now, Time.now, File.join(root, "coverage", ".resultset.json"))
        assert_equal 1_000, Coverage.load(root, FILES)["time"]
      end

      def test_invalid_json_and_a_wrong_shape_raise_with_the_path
        bad_json = root_with("{\"RSpec\": {")
        error = assert_raises(Coverage::Unreadable) { Coverage.load(bad_json, FILES) }
        assert_equal "coverage file unreadable: #{File.join(bad_json, 'coverage', '.resultset.json')}", error.message
        wrong_shape = root_with(JSON.generate("RSpec" => [1, 2]))
        assert_raises(Coverage::Unreadable) { Coverage.load(wrong_shape, FILES) }
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Itest -Ilib test/coverage_test.rb`
Expected: 7 errors, `NameError: uninitialized constant Uml::Viewer::Coverage`.

- [ ] **Step 3: Write `lib/uml/viewer/coverage.rb`**

```ruby
require "json"

module Uml
  module Viewer
    module Coverage
      class Unreadable < StandardError; end

      def self.load(root, scanned_files)
        path = File.join(root, "coverage", ".resultset.json")
        return nil unless File.exist?(path)

        resultset = JSON.parse(File.read(path))
        raise Unreadable, "coverage file unreadable: #{path}" unless suites?(resultset)

        parse(resultset, scanned_files)
      rescue JSON::ParserError, SystemCallError
        raise Unreadable, "coverage file unreadable: #{path}"
      end

      def self.suites?(resultset)
        resultset.is_a?(Hash) && resultset.values.all? { |suite| suite.is_a?(Hash) && suite["coverage"].is_a?(Hash) }
      end

      def self.parse(resultset, scanned_files)
        lines = {}
        resultset.each_value do |suite|
          suite["coverage"].each do |absolute, value|
            file = match(absolute, scanned_files)
            next if file.nil?

            lines[file] = add(lines[file], value.is_a?(Hash) ? value["lines"] : value)
          end
        end
        { "time" => resultset.values.filter_map { |suite| suite["timestamp"] }.max, "lines" => lines }
      end

      def self.match(absolute, scanned_files)
        scanned_files.select { |file| absolute == file || absolute.end_with?("/#{file}") }.max_by(&:size)
      end

      def self.add(sum, hits)
        return hits.dup if sum.nil?

        Array.new([sum.size, hits.size].max) do |index|
          left = sum[index]
          right = hits[index]
          left.nil? && right.nil? ? nil : left.to_i + right.to_i
        end
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/coverage"` directly after `require_relative "viewer/views"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Itest -Ilib test/coverage_test.rb`
Expected: `7 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Check that the tests can tell.** In `match`, replace `.max_by(&:size)` with `.min_by(&:size)`. Run the test. Expected: the longest-path test fails. Restore it.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/coverage.rb lib/uml/viewer.rb test/coverage_test.rb
git commit -m "feat: read SimpleCov result files in both formats and map them to scanned files"
```

---

### Task 3: Overlay

**Files:**
- Create: `lib/uml/viewer/overlay.rb`
- Modify: `lib/uml/viewer.rb`
- Test: `test/overlay_test.rb`

**Interfaces:**
- Consumes: the coverage hash of Task 2 (or nil); classes with `ops` (milestone 2).
- Produces:
  - `Overlay.apply(classes, coverage:, mtimes:, mutation:, cutoffs:, missing_note: Overlay::NO_COVERAGE) -> {"classes" => [...], "coverage" => {"time", "files", "scanned", "banner"}}`. `mtimes` maps each class file to its mtime (Float, or nil). `mutation` is the parsed snapshot or nil.
  - Each op gains `"coverage"` (Float 0..1, or nil) and `"crap"` (Float, or nil).
  - Each class gains `"coverage_notes"` ([String]), `"crap"` (`{"mu", "sigma", "grade"}` or nil), `"mutation"` (`{"score", "grade", "counts"}` or nil) and `"grade"` (the mean of the C and M grades that exist, Float, or nil).
  - `Overlay.boxes(views, classes, cutoffs) -> views` adds `"c_grade"`, `"m_grade"` and `"grade"` to every class, namespace and folder node, pooled over all methods under the node.
  - `Overlay.crap(cc, coverage)`, `Overlay.stats(values, cutoffs)`, `Overlay.grade(value, cutoffs)`.
  - Constants `NO_COVERAGE = "no coverage: run your tests with SimpleCov"`, `STALE = "coverage older than this file"`, `NOT_LOADED = "not loaded by the tests"`, `PARTIAL = "coverage looks partial: run the full suite"`.

- [ ] **Step 1: Write the failing test.** `test/overlay_test.rb`:

```ruby
require "test_helper"

module Uml
  module Viewer
    class OverlayTest < TestCase
      CUTOFFS = PolicyFile::DEFAULTS["crap_cutoffs"]

      def op(name, cc, line_start, line_end, file: "app/models/order.rb")
        { "name" => name, "visibility" => "public", "cc" => cc, "file" => file, "line_start" => line_start, "line_end" => line_end }
      end

      def klass(id, ops, files = ops.map { |entry| entry["file"] }.uniq)
        { "id" => id, "files" => files.empty? ? ["app/models/#{id.downcase}.rb"] : files, "ops" => ops }
      end

      def apply(classes, lines: {}, time: 100, mtimes: nil, mutation: nil, coverage: :given)
        mtimes ||= classes.flat_map { |entry| entry["files"] }.to_h { |file| [file, 50.0] }
        covered = coverage == :given ? { "time" => time, "lines" => lines } : coverage
        Overlay.apply(classes, coverage: covered, mtimes: mtimes, mutation: mutation, cutoffs: CUTOFFS)
      end

      def test_method_coverage_skips_the_def_line_so_a_hit_def_with_an_unhit_body_is_zero
        result = apply([klass("Admin", [op("to_s", 1, 1, 3)])], lines: { "app/models/order.rb" => [1, 0, nil] })
        assert_equal [0.0, 2.0], result["classes"].first["ops"].first.values_at("coverage", "crap")
      end

      def test_crap_has_the_cube_on_a_real_controller_action
        hits = [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, nil]
        result = apply([klass("Branches", [op("index", 10, 1, 17)])], lines: { "app/models/order.rb" => hits })
        coverage, crap = result["classes"].first["ops"].first.values_at("coverage", "crap")
        assert_in_delta 8.0 / 15, coverage, 0.0001
        assert_in_delta 20.16, crap, 0.01
      end

      def test_crap_at_coverage_zero_half_and_one
        assert_equal [20.0, 6.0, 4.0], [Overlay.crap(4, 0.0), Overlay.crap(4, 0.5), Overlay.crap(4, 1.0)]
      end

      def test_the_class_grade_is_mu_plus_sigma_with_the_population_sigma
        stats = Overlay.stats([20.16, 4.37, 5.0, 2.0, 8.13, 30.0, 3.01, 1.0], CUTOFFS)
        assert_in_delta 9.21, stats["mu"], 0.01
        assert_in_delta 9.70, stats["sigma"], 0.01
        assert_equal 7, stats["grade"]
        assert_in_delta 1.0, Overlay.stats([1.0, 3.0], CUTOFFS)["sigma"], 0.0001
      end

      def test_each_grade_cutoff_on_both_sides
        assert_equal [10, 9, 9, 8, 2, 1], [5, 5.01, 10, 10.01, 120, 120.01].map { |value| Overlay.grade(value, CUTOFFS) }
      end

      def test_an_endless_def_has_no_coverage_data_and_no_crap
        result = apply([klass("Order", [op("total", 1, 2, 2)])], lines: { "app/models/order.rb" => [nil, 1, nil] })
        assert_equal [nil, nil], result["classes"].first["ops"].first.values_at("coverage", "crap")
      end

      def test_lines_past_the_end_of_the_hit_array_are_not_relevant
        result = apply([klass("Order", [op("total", 1, 1, 6)])], lines: { "app/models/order.rb" => [1, 1] })
        assert_equal 1.0, result["classes"].first["ops"].first["coverage"]
      end

      def test_no_resultset_gives_no_data_and_the_simplecov_note
        result = apply([klass("Order", [op("total", 3, 1, 3)])], coverage: nil)
        entry = result["classes"].first
        assert_equal [nil, nil, ["no coverage: run your tests with SimpleCov"]], [entry["ops"].first["crap"], entry["crap"], entry["coverage_notes"]]
        assert_equal({ "time" => nil, "files" => 0, "scanned" => 1, "banner" => nil }, result["coverage"])
      end

      def test_a_file_changed_after_the_coverage_time_is_stale_and_grey
        classes = [klass("Order", [op("total", 1, 1, 3)])]
        result = apply(classes, lines: { "app/models/order.rb" => [1, 1, nil] }, time: 100, mtimes: { "app/models/order.rb" => 101.0 })
        assert_equal [nil, ["coverage older than this file"]], [result["classes"].first["ops"].first["coverage"], result["classes"].first["coverage_notes"]]
      end

      def test_a_file_absent_from_a_full_run_was_never_loaded_and_has_coverage_zero
        present = (1..6).map { |number| klass("Present#{number}", [op("run", 1, 1, 3, file: "app/models/present#{number}.rb")]) }
        absent = (1..4).map { |number| klass("Absent#{number}", [op("run", 2, 1, 3, file: "app/models/absent#{number}.rb")]) }
        lines = (1..6).to_h { |number| ["app/models/present#{number}.rb", [1, 1, nil]] }
        result = apply(present + absent, lines: lines)
        missing = result["classes"].find { |entry| entry["id"] == "Absent1" }
        assert_equal [0.0, 6.0, ["not loaded by the tests"]], [missing["ops"].first["coverage"], missing["ops"].first["crap"], missing["coverage_notes"]]
        assert_nil result["coverage"]["banner"]
      end

      def test_a_partial_run_leaves_absent_files_grey_and_shows_the_banner
        classes = (1..10).map { |number| klass("Item#{number}", [op("run", 1, 1, 3, file: "app/models/item#{number}.rb")]) }
        result = apply(classes, lines: { "app/models/item1.rb" => [1, 1, nil] })
        absent = result["classes"].find { |entry| entry["id"] == "Item2" }
        assert_equal [nil, ["coverage looks partial: run the full suite"]], [absent["ops"].first["coverage"], absent["coverage_notes"]]
        assert_equal "coverage looks partial: 1 of 10 files; run the full suite", result["coverage"]["banner"]
      end

      def test_a_class_without_crap_has_no_c_grade_even_with_a_high_cc
        result = apply([klass("Order", [op("total", 25, 2, 2)])], lines: { "app/models/order.rb" => [nil, 1, nil] })
        assert_equal [nil, nil], result["classes"].first.values_at("crap", "grade")
      end

      def test_a_class_without_ops_has_no_grade_and_no_error
        result = apply([klass("Limits", [], ["app/models/limits.rb"])], lines: { "app/models/limits.rb" => [nil] })
        assert_equal [nil, nil, nil], result["classes"].first.values_at("crap", "mutation", "grade")
      end

      def test_the_mutation_grade_sums_the_counts_of_the_class_methods
        classes = [klass("Order", [op("total", 1, 1, 3), op("self.build", 1, 4, 6), op("tax", 1, 7, 9)])]
        mutation = {
          "Order#total" => { "killed" => 3, "survived" => 1, "uncovered" => 0 },
          "Order.build" => { "killed" => 1, "survived" => 0, "uncovered" => 1 },
          "Order#gone" => { "killed" => 0, "survived" => 9, "uncovered" => 9 }
        }
        result = apply(classes, coverage: nil, mutation: mutation)["classes"].first
        assert_equal({ "killed" => 4, "survived" => 1, "uncovered" => 1 }, result["mutation"]["counts"])
        assert_in_delta 4.0 / 6, result["mutation"]["score"], 0.0001
        assert_equal [7, 7.0], [result["mutation"]["grade"], result["grade"]]
      end

      def test_a_mutation_score_of_zero_still_grades_one
        classes = [klass("Order", [op("total", 1, 1, 3)])]
        result = apply(classes, coverage: nil, mutation: { "Order#total" => { "killed" => 0, "survived" => 2, "uncovered" => 0 } })
        assert_equal 1, result["classes"].first["mutation"]["grade"]
      end

      def test_the_class_grade_is_the_mean_of_the_c_and_m_grades
        classes = [klass("Order", [op("total", 1, 1, 3)])]
        result = apply(classes, lines: { "app/models/order.rb" => [1, 1, nil] }, mutation: { "Order#total" => { "killed" => 1, "survived" => 1, "uncovered" => 0 } })
        assert_equal [10, 5, 7.5], [result["classes"].first["crap"]["grade"], result["classes"].first["mutation"]["grade"], result["classes"].first["grade"]]
      end

      def test_boxes_pool_every_method_under_a_box_with_one_weight_per_method
        classes = apply([
          klass("Billing::Counter", [op("a", 1, 1, 3, file: "app/services/billing/counter.rb")]),
          klass("Billing::Gateway::Client", [op("b", 4, 1, 3, file: "app/services/billing/gateway/client.rb"), op("c", 4, 4, 6, file: "app/services/billing/gateway/client.rb")]),
          klass("Billing::Limits", [], ["app/services/billing/limits.rb"])
        ], lines: { "app/services/billing/counter.rb" => [1, 1, nil], "app/services/billing/gateway/client.rb" => [1, 0, nil, 1, 0, nil], "app/services/billing/limits.rb" => [nil] })["classes"]
        entries = classes.map { |entry| entry.merge("kind_folder" => "services", "level" => 1, "stereotype" => "class") }
        views = Overlay.boxes(Views.build(entries, ["Billing", "Billing::Gateway"], [], []), classes, CUTOFFS)
        billing = views["root"]["nodes"].find { |node| node["id"] == "Billing" }
        assert_equal [Overlay.stats([1.0, 20.0, 20.0], CUTOFFS)["grade"], nil], billing.values_at("c_grade", "m_grade")
        client = views["Billing::Gateway"]["nodes"].find { |node| node["id"] == "Billing::Gateway::Client" }
        assert_equal Overlay.stats([20.0, 20.0], CUTOFFS)["grade"], client["c_grade"]
        limits = views["Billing"]["nodes"].find { |node| node["id"] == "Billing::Limits" }
        assert_equal [nil, nil, nil], limits.values_at("c_grade", "m_grade", "grade")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Itest -Ilib test/overlay_test.rb`
Expected: 17 errors, `NameError: uninitialized constant Uml::Viewer::Overlay`.

- [ ] **Step 3: Write `lib/uml/viewer/overlay.rb`**

```ruby
module Uml
  module Viewer
    module Overlay
      NO_COVERAGE = "no coverage: run your tests with SimpleCov".freeze
      STALE = "coverage older than this file".freeze
      NOT_LOADED = "not loaded by the tests".freeze
      PARTIAL = "coverage looks partial: run the full suite".freeze
      COUNTS = %w[killed survived uncovered].freeze

      def self.apply(classes, coverage:, mtimes:, mutation:, cutoffs:, missing_note: NO_COVERAGE)
        files = classes.flat_map { |entry| entry["files"] }.uniq
        present = coverage ? files.count { |file| coverage["lines"].key?(file) } : 0
        partial = !coverage.nil? && present < files.size / 2.0
        states = files.to_h { |file| [file, file_state(file, coverage, mtimes, partial)] }
        notes = { none: missing_note, stale: STALE, absent: NOT_LOADED, partial: PARTIAL }
        graded = classes.map do |entry|
          ops = entry["ops"].map { |op| with_metrics(op, states[op["file"]], coverage) }
          craps = ops.filter_map { |op| op["crap"] }
          crap = craps.empty? ? nil : stats(craps, cutoffs)
          counts = mutation_counts(entry["id"], ops, mutation)
          tested = counts && mutation_grade(counts)
          entry.merge(
            "ops" => ops, "coverage_notes" => entry["files"].filter_map { |file| notes[states[file]] }.uniq,
            "crap" => crap, "mutation" => tested, "grade" => mean_grade(crap, tested)
          )
        end
        { "classes" => graded, "coverage" => summary(coverage, present, files.size, partial) }
      end

      def self.file_state(file, coverage, mtimes, partial)
        return :none if coverage.nil?
        return :stale if mtimes[file].to_f > coverage["time"].to_f
        return :lines if coverage["lines"].key?(file)

        partial ? :partial : :absent
      end

      def self.with_metrics(op, state, coverage)
        value = case state
                when :absent then 0.0
                when :lines then body_coverage(op, coverage["lines"][op["file"]])
                end
        op.merge("coverage" => value, "crap" => value && crap(op["cc"], value))
      end

      def self.body_coverage(op, hits)
        body = ((op["line_start"] + 1)..(op["line_end"] - 1)).filter_map { |line| hits[line - 1] }
        body.empty? ? nil : body.count(&:positive?).fdiv(body.size)
      end

      def self.crap(cc, coverage)
        (cc**2) * ((1 - coverage)**3) + cc.to_f
      end

      def self.stats(values, cutoffs)
        mu = values.sum.fdiv(values.size)
        sigma = Math.sqrt(values.sum { |value| (value - mu)**2 }.fdiv(values.size))
        { "mu" => mu, "sigma" => sigma, "grade" => grade(mu + sigma, cutoffs) }
      end

      def self.grade(value, cutoffs)
        index = cutoffs.index { |cutoff| value <= cutoff }
        index ? 10 - index : 1
      end

      def self.mutation_counts(class_id, ops, mutation)
        return nil if mutation.nil?

        found = ops.filter_map { |op| mutation[mutation_key(class_id, op["name"])] }
        return nil if found.empty?

        COUNTS.to_h { |key| [key, found.sum { |entry| entry[key].to_i }] }
      end

      def self.mutation_key(class_id, name)
        name.start_with?("self.") ? "#{class_id}.#{name.delete_prefix('self.')}" : "#{class_id}##{name}"
      end

      def self.mutation_grade(counts)
        total = counts.values.sum
        return nil if total.zero?

        score = counts["killed"].fdiv(total)
        { "score" => score, "grade" => [1, (score * 10).ceil].max, "counts" => counts }
      end

      def self.mean_grade(crap, tested)
        grades = [crap&.fetch("grade"), tested&.fetch("grade")].compact
        grades.empty? ? nil : grades.sum.fdiv(grades.size)
      end

      def self.summary(coverage, present, scanned, partial)
        return { "time" => nil, "files" => 0, "scanned" => scanned, "banner" => nil } if coverage.nil?

        banner = partial ? "coverage looks partial: #{present} of #{scanned} files; run the full suite" : nil
        { "time" => coverage["time"], "files" => present, "scanned" => scanned, "banner" => banner }
      end

      def self.boxes(views, classes, cutoffs)
        by_id = classes.to_h { |entry| [entry["id"], entry] }
        memo = {}
        views.transform_values do |view|
          view.merge("nodes" => view["nodes"].map { |node| node.merge(node_grades(node, views, by_id, cutoffs, memo)) })
        end
      end

      def self.node_grades(node, views, by_id, cutoffs, memo)
        ids = case node["type"]
              when "class" then [node["id"]]
              when "namespace", "folder" then classes_under(node["id"], views, memo)
              else return {}
              end
        entries = ids.filter_map { |id| by_id[id] }
        craps = entries.flat_map { |entry| entry["ops"].filter_map { |op| op["crap"] } }
        counts = entries.filter_map { |entry| entry.dig("mutation", "counts") }
        crap = craps.empty? ? nil : stats(craps, cutoffs)
        tested = counts.empty? ? nil : mutation_grade(COUNTS.to_h { |key| [key, counts.sum { |count| count[key] }] })
        { "c_grade" => crap&.fetch("grade"), "m_grade" => tested&.fetch("grade"), "grade" => mean_grade(crap, tested) }
      end

      def self.classes_under(view_id, views, memo)
        memo[view_id] ||= views[view_id]["nodes"].flat_map do |node|
          case node["type"]
          when "class" then [node["id"]]
          when "namespace", "folder" then classes_under(node["id"], views, memo)
          else []
          end
        end
      end
    end
  end
end
```

In `lib/uml/viewer.rb`, add `require_relative "viewer/overlay"` directly after `require_relative "viewer/coverage"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Itest -Ilib test/overlay_test.rb`
Expected: `17 runs, 0 failures, 0 errors`.

- [ ] **Step 5: Check that the tests can tell.** In `crap`, change `((1 - coverage)**3)` to `(1 - coverage)`. Run the test. Expected: the real-controller test and the 0/0.5/1 test fail. Restore it. Then in `body_coverage`, change `(op["line_start"] + 1)` to `op["line_start"]`. Expected: the def-line test fails. Restore it.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/overlay.rb lib/uml/viewer.rb test/overlay_test.rb
git commit -m "feat: compute method coverage, CRAP and the C and M grades per class and per box"
```

---

### Task 4: Graph, PolicyFile, CLI and smoke

**Files:**
- Modify: `lib/uml/viewer/graph.rb`, `lib/uml/viewer/policy_file.rb`, `lib/uml/viewer/cli.rb`, `lib/uml/viewer/smoke.rb`
- Test: `test/graph_test.rb`, `test/policy_file_test.rb`, `test/cli_test.rb`, `test/smoke_test.rb`, `test/server_test.rb`

**Interfaces:**
- Consumes: `Coverage.load` (Task 2), `Overlay.apply` and `Overlay.boxes` (Task 3).
- Produces:
  - `graph.json` classes carry the overlay fields of Task 3; view nodes carry `c_grade`, `m_grade`, `grade`.
  - `graph["summary"]["coverage"]` is `{"time", "files", "scanned", "banner"}`; `banner` is the unreadable-file message or the partial-run message, or nil.
  - An unreadable mutation snapshot adds `"mutation snapshot unreadable: <path>"` to `graph["summary"]["warnings"]`.
  - `Graph.coverage_line(coverage_summary) -> String`: `"coverage: N of M files from <ISO 8601 UTC time>"`, or `"coverage: none"`.
  - `Graph.inputs` also lists `<root>/coverage/.resultset.json` and the state folder's `mutation.json`.
  - `PolicyFile.load` raises `Invalid` with `"policy.yml: crap_cutoffs must be 9 numbers in rising order"`.
  - `uml-viewer scan` prints the coverage line after the `unlisted foreign:` line, then the warnings (with the coverage banner as one more `warning:` line). Smoke prints the coverage line under each project's counts line.

- [ ] **Step 1: Write the failing tests.** Add to `test/graph_test.rb`:

```ruby
      def write_coverage(project, text)
        FileUtils.mkdir_p(File.join(project, "coverage"))
        File.write(File.join(project, "coverage", ".resultset.json"), text)
      end

      def resultset_for(project, lines_by_file, timestamp: Time.now.to_i + 60)
        JSON.generate("RSpec" => { "coverage" => lines_by_file.transform_keys { |file| File.join(project, file) }, "timestamp" => timestamp })
      end

      def test_the_overlay_reaches_the_classes_the_views_and_the_summary
        project = project_copy
        write_coverage(project, resultset_for(project, { "app/services/pricing.rb" => [nil, 1, 1, nil, nil] }))
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        graph = Graph.build(workspace)
        pricing = graph["classes"].find { |entry| entry["id"] == "Pricing" }
        assert_equal [1.0, 1.0, 10], [pricing["ops"].first["coverage"], pricing["ops"].first["crap"], pricing["crap"]["grade"]]
        services = graph["views"]["root"]["nodes"].find { |node| node["id"] == "folder:services" }
        assert services.key?("c_grade")
        assert_equal 1, graph["summary"]["coverage"]["files"]
        assert_operator graph["summary"]["coverage"]["scanned"], :>, 1
      end

      def test_an_unreadable_coverage_file_still_writes_the_graph_with_the_banner_and_recovers
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        write_coverage(project, "{\"RSpec\": {")
        graph = Graph.build(workspace)
        path = File.join(workspace.root, "coverage", ".resultset.json")
        assert_equal "coverage file unreadable: #{path}", graph["summary"]["coverage"]["banner"]
        assert_equal ["coverage file unreadable: #{path}"], graph["classes"].find { |entry| entry["id"] == "Pricing" }["coverage_notes"]
        write_coverage(project, resultset_for(project, { "app/services/pricing.rb" => [nil, 1, 1, nil, nil] }))
        assert_nil Graph.build(workspace)["summary"]["coverage"]["banner"]
      end

      def test_a_mutation_snapshot_gives_m_grades_and_a_broken_one_a_warning
        workspace = Workspace.new(project_copy)
        Graph.prepare(workspace)
        workspace.write_atomic("mutation.json", JSON.generate("Pricing#initialize" => { "killed" => 9, "survived" => 1, "uncovered" => 0 }))
        assert_equal 9, Graph.build(workspace)["classes"].find { |entry| entry["id"] == "Pricing" }["mutation"]["grade"]
        workspace.write_atomic("mutation.json", "[1, 2]")
        assert_includes Graph.build(workspace)["summary"]["warnings"], "mutation snapshot unreadable: #{workspace.path('mutation.json')}"
      end

      def test_the_coverage_line_names_the_files_and_the_time
        assert_equal "coverage: 3 of 10 files from 2024-04-25T10:52:50Z", Graph.coverage_line("time" => 1_714_042_370, "files" => 3, "scanned" => 10, "banner" => nil)
        assert_equal "coverage: none", Graph.coverage_line("time" => nil, "files" => 0, "scanned" => 10, "banner" => nil)
      end

      def test_inputs_list_the_coverage_file_and_the_mutation_snapshot
        workspace = Workspace.new(project_copy)
        Graph.prepare(workspace)
        inputs = Graph.inputs(workspace)
        assert_includes inputs.keys, File.join(workspace.root, "coverage", ".resultset.json")
        assert_includes inputs.keys, workspace.path("mutation.json")
      end
```

Add to `test/policy_file_test.rb`:

```ruby
      def test_crap_cutoffs_must_be_nine_rising_numbers
        ["crap_cutoffs: [5, 10]\n", "crap_cutoffs: [5, 10, 15, 20, 30, 40, 60, 80, 70]\n", "crap_cutoffs: [a, 10, 15, 20, 30, 40, 60, 80, 120]\n"].each do |text|
          error = assert_raises(PolicyFile::Invalid, text) { PolicyFile.load(write(text)) }
          assert_equal "policy.yml: crap_cutoffs must be 9 numbers in rising order", error.message
        end
        assert_equal [1, 2, 3, 4, 5, 6, 7, 8, 9], PolicyFile.load(write("crap_cutoffs: [1, 2, 3, 4, 5, 6, 7, 8, 9]\n"))["crap_cutoffs"]
      end
```

In `test/cli_test.rb`, in `test_scan_prints_the_association_counts_and_each_warning`, change the last assertion to check the coverage line and the warnings after it:

```ruby
        assert_equal "coverage: none", lines[3]
        assert_equal ["warning: levels: unknown folder workers"], lines.drop(4)
```

Add to `test/smoke_test.rb`:

```ruby
      def test_smoke_prints_the_coverage_line_of_each_project
        out = StringIO.new
        Smoke.run([git_project], out: out)
        assert_includes out.string.lines(chomp: true), "  coverage: none"
      end
```

Add to `test/server_test.rb`:

```ruby
      def test_a_new_coverage_file_rescans_and_colors_the_graph
        FileUtils.mkdir_p(File.join(@project, "coverage"))
        File.write(File.join(@project, "coverage", ".resultset.json"),
                   JSON.generate("RSpec" => { "coverage" => { File.join(@workspace.root, "app/services/pricing.rb") => [nil, 1, 1, nil, nil] }, "timestamp" => Time.now.to_i + 60 }))
        wait_for_graph("the coverage file never reached the graph") do |graph|
          graph["classes"].find { |entry| entry["id"] == "Pricing" }["crap"]
        end
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/graph_test.rb && bundle exec ruby -Itest -Ilib test/policy_file_test.rb && bundle exec ruby -Itest -Ilib test/cli_test.rb -n /association_counts/ && bundle exec ruby -Itest -Ilib test/smoke_test.rb -n /coverage/ && bundle exec ruby -Itest -Ilib test/server_test.rb -n /coverage/`
Expected: the graph tests fail on the missing overlay keys and `Graph.coverage_line`; the cutoffs test gets no exception; the CLI test finds the warning line at index 3; smoke has no coverage line; the server test times out.

- [ ] **Step 3: Validate the cutoffs.** In `lib/uml/viewer/policy_file.rb`, in `validate`, before `policy` is returned, add:

```ruby
        cutoffs = policy["crap_cutoffs"]
        unless cutoffs.is_a?(Array) && cutoffs.size == 9 && cutoffs.all?(Numeric) && cutoffs.each_cons(2).all? { |low, high| low < high }
          raise Invalid, "policy.yml: crap_cutoffs must be 9 numbers in rising order"
        end
```

- [ ] **Step 4: Run the overlay in the graph.** In `lib/uml/viewer/graph.rb`, add `require "time"` at the top, and replace `build` with:

```ruby
      def self.build(workspace)
        policy = PolicyFile.load(workspace.path("policy.yml"))
        scan = Scanner.new(workspace.root, sources: policy["sources"], skip: policy["skip"]).scan
        applied = Policy.apply(scan, policy)
        files = applied["classes"].flat_map { |entry| entry["files"] }.uniq
        coverage, coverage_error = load_coverage(workspace, files)
        mutation, mutation_error = load_mutation(workspace)
        overlay = Overlay.apply(applied["classes"], coverage: coverage, mutation: mutation, cutoffs: policy["crap_cutoffs"],
                                                    mtimes: files.to_h { |file| [file, mtime(File.join(workspace.root, file))] },
                                                    missing_note: coverage_error || Overlay::NO_COVERAGE)
        summary = summary(scan, applied, policy)
        summary["coverage"] = overlay["coverage"].merge("banner" => coverage_error || overlay["coverage"]["banner"])
        summary["warnings"] += [mutation_error].compact
        graph = {
          "version" => 2,
          "title" => policy["title"].empty? ? File.basename(workspace.root) : policy["title"],
          "proposals" => policy["proposals"],
          "summary" => summary,
          "namespaces" => applied["namespaces"],
          "classes" => overlay["classes"],
          "edges" => applied["edges"],
          "views" => Overlay.boxes(applied["views"], overlay["classes"], policy["crap_cutoffs"])
        }
        workspace.write_atomic("graph.json", JSON.generate(graph))
        graph
      end

      def self.load_coverage(workspace, files)
        [Coverage.load(workspace.root, files), nil]
      rescue Coverage::Unreadable => error
        [nil, error.message]
      end

      def self.load_mutation(workspace)
        path = workspace.path("mutation.json")
        return [nil, nil] unless File.exist?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Hash) && data.values.all?(Hash) ? [data, nil] : [nil, "mutation snapshot unreadable: #{path}"]
      rescue JSON::ParserError, SystemCallError
        [nil, "mutation snapshot unreadable: #{path}"]
      end

      def self.coverage_line(coverage)
        return "coverage: none" if coverage["time"].nil?

        "coverage: #{coverage['files']} of #{coverage['scanned']} files from #{Time.at(coverage['time']).utc.iso8601}"
      end
```

In `inputs`, change the list of paths to also hold the two overlay inputs:

```ruby
        extra = [File.join(workspace.root, "coverage", ".resultset.json"), workspace.path("mutation.json")]
        ([workspace.path("policy.yml")] + extra + files.map { |file| File.join(workspace.root, file) }).to_h { |path| [path, mtime(path)] }
```

- [ ] **Step 5: Print the coverage line.** In `lib/uml/viewer/cli.rb`, in `run_scan`, after the `unlisted foreign:` line and before the warnings, add:

```ruby
        @out.puts Graph.coverage_line(summary["coverage"])
        summary["warnings"] += [summary["coverage"]["banner"]].compact
```

(Keep the existing `summary["warnings"].each { |warning| @out.puts "warning: #{warning}" }` after it.)

In `lib/uml/viewer/smoke.rb`, in `check`, directly after the counts line (`out.puts "#{name}: ..."`), add:

```ruby
        out.puts "  #{Graph.coverage_line(graph['summary']['coverage'])}"
```

- [ ] **Step 6: Run the tests**

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 7: Check that the tests can tell.** In `Graph.build`, change `missing_note: coverage_error || Overlay::NO_COVERAGE` to `missing_note: Overlay::NO_COVERAGE`. Run `test/graph_test.rb -n /unreadable/`. Expected: it fails on the card note. Restore it.

- [ ] **Step 8: Commit**

```bash
git add lib/uml/viewer/graph.rb lib/uml/viewer/policy_file.rb lib/uml/viewer/cli.rb lib/uml/viewer/smoke.rb test/graph_test.rb test/policy_file_test.rb test/cli_test.rb test/smoke_test.rb test/server_test.rb
git commit -m "feat: add the coverage overlay to the graph, rescan on a new coverage file, and print the coverage line"
```

---

### Task 5: The page: grade colors, C and M dots, card metrics, coverage banner

**Files:**
- Modify: `lib/uml/viewer/web/index.html`, `lib/uml/viewer/web/app.js`
- Test: `test/browser_test.rb`

**Interfaces:**
- Consumes: view nodes with `grade`, `c_grade`, `m_grade`; classes with `crap`, `mutation`, `coverage_notes`, and ops with `coverage` and `crap` (Task 4); `graph.summary.coverage.banner`.
- Produces (DOM contract):
  - Every `g.box` of type class, namespace or folder has `data-grade` (the grade, or an empty string) and its `rect` filled by grade: a hue from red (grade 1) to green (grade 10), neutral `var(--box)` with no grade.
  - Two `circle.dot` per such box: `circle.dot.c` and `circle.dot.m`, each with `data-grade`, grey (`var(--muted)`) with no grade.
  - The card shows `C grade N (mu X.X, sigma X.X)` or `C grade: no data`, `M grade N (score P%)` or `M grade: no data`, one `p.note.coverage` per coverage note, and each op as `<sign> <name>  cc N  cov P%  crap X.X` when the op has coverage (unchanged `<sign> <name>  cc N` without).
  - The banner shows `graph.summary.coverage.banner` when no other banner applies.

- [ ] **Step 1: Write the failing tests.** Add to `test/browser_test.rb` (helper first):

```ruby
      def boot_coverage_project(resultset: :valid)
        project = build_project(
          "app/models/order.rb" => "class Order\n  def total\n    1\n  end\nend\n",
          "app/services/pricing.rb" => "class Pricing\n  def rate(x)\n    x ? 1 : 2\n  end\nend\n"
        )
        FileUtils.mkdir_p(File.join(project, "coverage"))
        text = if resultset == :valid
                 JSON.generate("RSpec" => { "coverage" => { File.join(File.realpath(project), "app/models/order.rb") => [nil, 1, 1, nil, nil] }, "timestamp" => Time.now.to_i + 60 })
               else
                 "{\"RSpec\": {"
               end
        File.write(File.join(project, "coverage", ".resultset.json"), text)
        reboot(project)
      end

      def test_a_covered_class_shows_its_grade_color_dots_and_metrics_on_the_card
        boot_coverage_project
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"][data-grade="10"]')
        assert_equal "10", @browser.at_css('g.box[data-id="folder:models"] circle.dot.c').attribute("data-grade")
        assert_equal "", @browser.at_css('g.box[data-id="folder:models"] circle.dot.m').attribute("data-grade")
        double_click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "C grade 10 (mu 1.0, sigma 0.0)"
        assert_includes @browser.at_css("#card").text, "M grade: no data"
        assert_includes op_texts, "+ total  cc 1  cov 100%  crap 1.0"
      end

      def test_a_class_the_tests_never_loaded_shows_coverage_zero_and_the_note
        boot_coverage_project
        @browser.goto(@server.url)
        double_click('text.member[data-id="Pricing"]')
        wait_for_text("#card h2", "Pricing")
        assert_includes op_texts, "+ rate  cc 2  cov 0%  crap 6.0"
        assert_equal ["not loaded by the tests"], @browser.css("#card p.note.coverage").map(&:text)
      end

      def test_a_project_without_coverage_shows_grey_dots_and_the_simplecov_note
        @browser.goto(@server.url)
        wait_for('g.box[data-id="folder:models"] circle.dot.c')
        assert_equal "", @browser.at_css('g.box[data-id="folder:models"]').attribute("data-grade")
        double_click('text.member[data-id="Order"]')
        wait_for_text("#card h2", "Order")
        assert_includes @browser.at_css("#card").text, "C grade: no data"
        assert_includes @browser.css("#card p.note.coverage").map(&:text), "no coverage: run your tests with SimpleCov"
      end

      def test_an_unreadable_coverage_file_shows_the_banner
        boot_coverage_project(resultset: :broken)
        @browser.goto(@server.url)
        wait_for_text("#banner", "coverage file unreadable:")
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb -n /coverage|grade|never_loaded/`
Expected: 4 failures: no `data-grade`, no dots, no metrics on the card, no coverage banner.

- [ ] **Step 3: Add the color tokens.** In `lib/uml/viewer/web/index.html`, add `--grade-l: 86%;` to the light `:root` and `--grade-l: 30%;` to the dark `:root`, and add this rule before `</style>`:

```css
  circle.dot { stroke: var(--line); stroke-width: 0.5; }
```

- [ ] **Step 4: Draw and show the grades.** In `lib/uml/viewer/web/app.js`:

  1. Add after `levelText`:

```js
  const hue = (grade) => Math.round(((grade - 1) / 9) * 120);
  const hasGrade = (grade) => grade !== null && grade !== undefined;
  const boxFill = (grade) => (hasGrade(grade) ? `hsl(${hue(grade)}, 55%, var(--grade-l))` : "var(--box)");
  const dotFill = (grade) => (hasGrade(grade) ? `hsl(${hue(grade)}, 65%, 45%)` : "var(--muted)");
```

  2. In `drawNode`, replace the line that draws the box `rect` with:

```js
    group.setAttribute("data-grade", hasGrade(node.grade) ? node.grade : "");
    el("rect", { width: placed.width, height: placed.height, rx: 4, style: `fill: ${boxFill(node.grade)}` }, group);
    [["c", node.c_grade], ["m", node.m_grade]].forEach(([kind, grade], index) => {
      el("circle", { class: `dot ${kind}`, cx: placed.width - 26 + 12 * index, cy: placed.height - 9, r: 4, "data-grade": hasGrade(grade) ? grade : "", style: `fill: ${dotFill(grade)}` }, group);
    });
```

  3. In `showBanner`, change the body to:

```js
    const coverage = graph && graph.summary && graph.summary.coverage && graph.summary.coverage.banner;
    banner.textContent = drawError || (scanError ? `${scanError}; showing last good graph` : "") || coverage || "";
```

  4. In `openCard`, after the line that appends the stereotype and level paragraph, add:

```js
    append(card, "p", entry.crap ? `C grade ${entry.crap.grade} (mu ${entry.crap.mu.toFixed(1)}, sigma ${entry.crap.sigma.toFixed(1)})` : "C grade: no data", "grade c");
    append(card, "p", entry.mutation ? `M grade ${entry.mutation.grade} (score ${Math.round(entry.mutation.score * 100)}%)` : "M grade: no data", "grade m");
    (entry.coverage_notes || []).forEach((note) => append(card, "p", note, "note coverage"));
```

  5. In `openCard`, change the op text to:

```js
      const metrics = hasGrade(op.coverage) ? `  cov ${Math.round(op.coverage * 100)}%  crap ${op.crap.toFixed(1)}` : "";
      const item = append(list, "li", `${SIGNS[op.visibility]} ${op.name}  cc ${op.cc}${metrics}`, "op");
```

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest -Ilib test/browser_test.rb`
Expected: all pass (the existing card tests keep `+ total  cc 1`, because the fixture has no coverage file).

Run: `bundle exec rake test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/uml/viewer/web/index.html lib/uml/viewer/web/app.js test/browser_test.rb
git commit -m "feat: color boxes by grade, draw C and M dots, and show coverage and CRAP on the class card"
```

---

### Task 6: Backlog, README and the real-project check

**Files:**
- Modify: `docs/backlog.md`, `README.md`
- Outside the repository: a check script in the scratchpad

**Interfaces:**
- Consumes: everything above.
- Produces: an up-to-date backlog and README, a passing smoke run, and a recorded check of the six real examples.

- [ ] **Step 1: Backlog.** In `docs/backlog.md`, delete the line "`crap_cutoffs` is not validated." (fixed in Task 4). Change the first heading to `# Backlog after milestone 3`.

- [ ] **Step 2: README.** After the navigation paragraph, add:

```
Box colors show test quality: green is a good grade, red a poor one, and grey means no data. The class card says why. Run your tests with SimpleCov to get coverage and CRAP; put a mutation snapshot in the state folder (`uml-viewer path`) as `mutation.json` to get M grades.
```

- [ ] **Step 3: Smoke on the three apps**

Run: `UML_VIEWER_SMOKE=<medium app path>:<large app path>:<legacy app path> bundle exec rake smoke`
Expected: exit 0; each counts line is followed by a coverage line: `coverage: none` for the medium and large app, `coverage: 309 of 316 files from 2024-04-25T10:52:50Z` for the legacy app.

- [ ] **Step 4: Check the real examples.** Write a script in the scratchpad (never in the repository) that runs `Graph.prepare` and `Graph.build` on the legacy app's workspace and prints, for the real classes behind examples A to E (the controller gives the names in the dispatch): the op coverage and CRAP (A, B), the class `crap` mu, sigma and grade (C), the coverage notes of the absent controller (D), and the number of classes whose notes include "coverage older than this file" (E). Expected: A coverage 0.0, CRAP 2.0; B CRAP 20.16; C mu 9.21, sigma 9.70, grade 7; D ["not loaded by the tests"]; E 39 files' classes carry the stale note. Record the output in the report; it stays in the git-ignored workspace.

- [ ] **Step 5: Commit**

```bash
git add docs/backlog.md README.md
git commit -m "docs: remove the crap_cutoffs backlog item and describe the grade colors in the README"
```
