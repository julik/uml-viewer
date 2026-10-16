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
        values = [5, 5.01, 10, 10.01, 15, 15.01, 20, 20.01, 30, 30.01, 40, 40.01, 60, 60.01, 80, 80.01, 120, 120.01]
        assert_equal [10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1], values.map { |value| Overlay.grade(value, CUTOFFS) }
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
        assert_equal 1, missing["crap"]["grade"]
        assert_nil result["coverage"]["banner"]
      end

      def test_a_loaded_class_that_no_test_runs_is_grade_one_and_one_tested_method_lifts_it
        untested = klass("Untested", [op("a", 1, 1, 3), op("b", 1, 4, 6)])
        tested = klass("Tested", [op("a", 1, 1, 3, file: "app/models/tested.rb"), op("b", 1, 4, 6, file: "app/models/tested.rb")])
        lines = { "app/models/order.rb" => [1, 0, nil, 1, 0, nil], "app/models/tested.rb" => [1, 0, nil, 1, 1, nil] }
        result = apply([untested, tested], lines: lines)["classes"]
        assert_equal [1, 10], result.map { |entry| entry["crap"]["grade"] }
      end

      def test_the_partial_guard_is_fewer_than_half
        build = lambda do |present|
          classes = (1..10).map { |number| klass("Item#{number}", [op("run", 1, 1, 3, file: "app/models/item#{number}.rb")]) }
          apply(classes, lines: (1..present).to_h { |number| ["app/models/item#{number}.rb", [1, 1, nil]] })["coverage"]["banner"]
        end
        assert_equal "coverage looks partial: 4 of 10 files; run the full suite", build.call(4)
        assert_nil build.call(5)
      end

      def test_a_file_changed_at_the_coverage_time_is_not_stale
        result = apply([klass("Order", [op("total", 1, 1, 3)])], lines: { "app/models/order.rb" => [1, 1, nil] }, time: 100, mtimes: { "app/models/order.rb" => 100.0 })
        assert_equal 1.0, result["classes"].first["ops"].first["coverage"]
      end

      def test_a_hit_end_line_does_not_count
        result = apply([klass("Order", [op("total", 1, 1, 3)])], lines: { "app/models/order.rb" => [1, 0, 1] })
        assert_equal 0.0, result["classes"].first["ops"].first["coverage"]
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

      def test_a_mutation_score_of_zero_still_grades_one_and_a_third_rounds_up
        classes = [klass("Order", [op("total", 1, 1, 3)])]
        result = apply(classes, coverage: nil, mutation: { "Order#total" => { "killed" => 0, "survived" => 2, "uncovered" => 0 } })
        assert_equal 1, result["classes"].first["mutation"]["grade"]
        result = apply(classes, coverage: nil, mutation: { "Order#total" => { "killed" => 1, "survived" => 1, "uncovered" => 1 } })
        assert_equal 4, result["classes"].first["mutation"]["grade"]
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
        assert_equal [6, nil], billing.values_at("c_grade", "m_grade")
        client = views["Billing::Gateway"]["nodes"].find { |node| node["id"] == "Billing::Gateway::Client" }
        assert_equal 1, client["c_grade"]
        limits = views["Billing"]["nodes"].find { |node| node["id"] == "Billing::Limits" }
        assert_equal [nil, nil, nil], limits.values_at("c_grade", "m_grade", "grade")
      end

      def test_a_box_whose_measured_methods_all_have_coverage_zero_gets_c_grade_one_and_one_covered_method_keeps_the_crap_grade
        classes = apply([
          klass("Dead::First", [op("a", 1, 1, 3, file: "app/services/dead/first.rb")]),
          klass("Dead::Second", [op("b", 1, 1, 3, file: "app/services/dead/second.rb")]),
          klass("Live::First", [op("a", 1, 1, 3, file: "app/services/live/first.rb")]),
          klass("Live::Second", [op("b", 1, 1, 3, file: "app/services/live/second.rb")])
        ], lines: {
          "app/services/dead/first.rb" => [1, 0, nil], "app/services/dead/second.rb" => [1, 0, nil],
          "app/services/live/first.rb" => [1, 0, nil], "app/services/live/second.rb" => [1, 1, nil]
        })["classes"]
        entries = classes.map { |entry| entry.merge("kind_folder" => "services", "level" => 1, "stereotype" => "class") }
        nodes = Overlay.boxes(Views.build(entries, ["Dead", "Live"], [], []), classes, CUTOFFS)["root"]["nodes"]
        assert_equal [1, 10], %w[Dead Live].map { |id| nodes.find { |node| node["id"] == id }["c_grade"] }
      end
    end
  end
end
