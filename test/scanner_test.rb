require "test_helper"

module Uml
  module Viewer
    class ScannerTest < TestCase
      def scan
        @scan ||= Scanner.new(fixture).scan
      end

      def klass(id)
        scan["classes"].find { |entry| entry["id"] == id }
      end

      def edge?(from, to, in_scan: scan)
        in_scan["edges"].any? { |edge| edge["from"] == from && edge["to"] == to }
      end

      def project(files)
        root = Dir.mktmpdir("uml-viewer-project")
        @project_parents << root
        files.each do |path, source|
          FileUtils.mkdir_p(File.dirname(File.join(root, path)))
          File.write(File.join(root, path), source)
        end
        root
      end

      def test_a_constant_inside_a_class_gives_an_edge_to_that_class
        assert edge?("Order", "Reports::Summary")
      end

      def test_a_namespaced_class_refers_to_a_top_level_class
        assert edge?("Reports::Summary", "Order")
      end

      def test_a_compact_class_refers_to_a_sibling
        assert edge?("Shop::Customer", "Shop::Store")
      end

      def test_a_nested_class_refers_to_a_sibling
        assert edge?("Stats::Event", "Stats::Visit")
      end

      def test_a_bare_unknown_constant_is_foreign_and_gives_no_self_edge
        refute edge?("Reports::Summary", "Reports::Summary")
        assert_includes scan["foreign"].map(&:first), "JSON"
      end

      def test_a_self_reference_gives_no_edge
        refute edge?("Order", "Order")
      end

      def test_a_superclass_is_a_dependency_edge_in_milestone_1
        assert_equal "dependency", scan["edges"].find { |e| e["from"] == "User" && e["to"] == "ApplicationRecord" }["kind"]
      end

      def test_compact_and_nested_forms_both_give_the_full_constant
        assert klass("Shop::Customer")
        assert klass("Stats::Event")
      end

      def test_a_wrapper_module_is_a_namespace_not_a_class
        assert_nil klass("Stats")
        assert_nil klass("Billing")
        assert_includes scan["namespaces"], "Stats"
        assert_includes scan["namespaces"], "Billing"
      end

      def test_the_main_constant_matches_the_file_name_and_the_other_constant_is_not_a_class
        assert_equal "app/services/billing/counter.rb", klass("Billing::Counter")["file"]
        assert_nil klass("Billing::CounterError")
      end

      def test_a_file_whose_path_does_not_match_its_constant_takes_the_constant_from_the_code
        assert_equal "app/services/legacy/old_name.rb", klass("Legacy::Renamed")["file"]
        assert edge?("Legacy::Renamed", "Order")
      end

      def test_a_data_define_constant_declares_a_data_class
        assert_equal "data", klass("Schedule::Slot")["stereotype"]
        assert_includes scan["namespaces"], "Schedule"
      end

      def test_a_class_and_a_namespace_can_share_an_id
        assert klass("Payments")
        assert_includes scan["namespaces"], "Payments"
        assert edge?("Payments", "Payments::Gateway")
      end

      def test_a_concern_maps_to_the_folder_above_concerns
        assert_equal "models", klass("Trackable")["kind_folder"]
        assert_equal "concern", klass("Trackable")["stereotype"]
      end

      def test_kind_folder_is_the_first_folder_under_app_and_lib_for_lib
        assert_equal "services", klass("Reports::Summary")["kind_folder"]
        assert_equal "controllers", klass("OrdersController")["kind_folder"]
      end

      def test_a_broken_file_keeps_its_class_and_records_the_errors_with_lines
        broken = klass("Broken")
        refute_empty broken["parse_errors"]
        assert_match(/\Aline \d+: /, broken["parse_errors"].first)
      end

      def test_a_script_without_a_constant_is_skipped_and_reported
        assert_equal ["lib/scripts/run_once.rb"], scan["skipped"]
      end

      def test_assets_views_and_test_folders_are_not_scanned
        assert_nil klass("AssetsIgnored")
        assert_nil klass("OrderTest")
      end

      def test_skip_in_the_policy_drops_a_path
        scan = Scanner.new(fixture, skip: ["app/controllers"]).scan
        assert_nil scan["classes"].find { |entry| entry["id"] == "OrdersController" }
      end

      def test_foreign_counts_are_sorted_by_use_and_capped_at_20
        counts = scan["foreign"].map(&:last)
        assert_equal counts.sort.reverse, counts
        assert_operator scan["foreign"].size, :<=, 20
      end

      def test_a_reference_to_a_secondary_constant_of_a_file_gives_an_edge_to_its_main_class
        root = project(
          "app/services/billing/counter.rb" => "module Billing\n  class Counter\n  end\n\n  class CounterError < StandardError\n  end\nend\n",
          "app/services/invoice.rb" => "class Invoice\n  def fail! = raise(Billing::CounterError)\nend\n"
        )
        result = Scanner.new(root).scan
        assert edge?("Invoice", "Billing::Counter", in_scan: result)
        refute_includes result["foreign"].map(&:first), "Billing"
      end

      def test_a_main_class_of_one_file_wins_over_the_same_secondary_constant_in_a_later_file
        root = project(
          "app/services/caller.rb" => "class Caller\n  def entry = Registry::Entry.new\nend\n",
          "app/services/registry/entry.rb" => "class Registry::Entry\nend\n",
          "app/services/z_registry.rb" => "class Registry\n  def size = 0\n\n  class Entry\n  end\nend\n"
        )
        result = Scanner.new(root).scan
        assert edge?("Caller", "Registry::Entry", in_scan: result)
        refute edge?("Caller", "Registry", in_scan: result)
      end

      def test_a_constant_read_inside_its_own_class_is_not_foreign
        refute_includes scan["foreign"].map(&:first), "STATUS_LABELS"
      end

      def test_more_than_20_unknown_constants_give_exactly_20_foreign_entries
        names = ("A".."U").map { |letter| "Unknown#{letter}" }
        root = project("app/services/caller.rb" => "class Caller\n#{names.map { |name| "  def #{name.downcase} = #{name}\n" }.join}end\n")
        result = Scanner.new(root).scan
        assert_equal 21, names.size
        assert_equal 20, result["foreign"].size
      end
    end
  end
end
