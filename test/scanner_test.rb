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

def test_has_one_and_belongs_to_keep_a_final_s_and_habtm_singularizes
  root = project(
    "app/models/address.rb" => "class Address\nend\n",
    "app/models/status.rb" => "class Status\nend\n",
    "app/models/category.rb" => "class Category\nend\n",
    "app/models/order.rb" => "class Order\n  has_one :address\n  belongs_to :status\n  has_and_belongs_to_many :categories\nend\n"
  )
  result = Scanner.new(root).scan
  assert_equal %w[Address Category Status], result["edges"].select { |edge| edge["from"] == "Order" }.map { |edge| edge["to"] }
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

def test_folders_lists_the_kind_folders_that_exist_on_disk
  assert_equal %w[controllers lib models services], scan["folders"]
end

def test_an_unresolved_reference_gives_a_foreign_edge_to_its_first_segment
  root = project("app/services/pricing.rb" => "class Pricing < Base::Calculator\n  def http = Faraday::Connection.new\nend\n")
  result = Scanner.new(root).scan
  assert_equal [["Pricing", "Base", "inheritance"], ["Pricing", "Faraday", "dependency"]],
               result["foreign_edges"].map { |edge| edge.values_at("from", "to", "kind") }
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

      def test_foreign_counts_are_sorted_by_use
        counts = scan["foreign"].map(&:last)
        assert_equal counts.sort.reverse, counts
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

      def test_a_superclass_and_a_data_block_belong_to_the_class_of_their_own_file_when_the_namespace_is_another_class
        root = project(
          "app/services/pricing.rb" => "class Pricing\nend\n",
          "app/models/order.rb" => "class Order\n  def total = 0\nend\n",
          "app/models/order/line.rb" => "class Order\n  class Line < Pricing\n  end\nend\n",
          "app/services/payments.rb" => "class Payments\nend\n",
          "app/services/payments/gateway.rb" => "module Payments\n  Result = Data.define(:ok) do\n    def price = Pricing.new\n  end\nend\n"
        )
        result = Scanner.new(root).scan
        assert edge?("Order::Line", "Pricing", in_scan: result)
        assert edge?("Payments::Result", "Pricing", in_scan: result)
        refute edge?("Order", "Pricing", in_scan: result)
        refute edge?("Payments", "Pricing", in_scan: result)
      end

      def test_struct_new_with_and_without_a_block_declares_a_data_class
        root = project(
          "app/services/point.rb" => "Point = Struct.new(:x)\n",
          "app/services/shapes/circle.rb" => "module Shapes\n  Circle = Struct.new(:radius) do\n    def area = radius * radius\n  end\nend\n"
        )
        result = Scanner.new(root).scan
        assert_equal ["Point", "Shapes::Circle"], result["classes"].map { |entry| entry["id"] }
        assert_equal ["data", "data"], result["classes"].map { |entry| entry["stereotype"] }
      end

      def test_class_new_with_and_without_a_block_declares_a_data_class
        root = project(
          "app/services/errors/timeout.rb" => "module Errors\n  Timeout = Class.new(StandardError)\nend\n",
          "app/services/errors/retry.rb" => "module Errors\n  Retry = Class.new do\n    def wait = 1\n  end\nend\n"
        )
        result = Scanner.new(root).scan
        assert_equal ["Errors::Retry", "Errors::Timeout"], result["classes"].map { |entry| entry["id"] }
        assert_equal ["data", "data"], result["classes"].map { |entry| entry["stereotype"] }
      end

      def test_a_constant_read_inside_its_own_class_is_not_foreign
        refute_includes scan["foreign"].map(&:first), "STATUS_LABELS"
      end

      def test_the_scan_keeps_every_foreign_name_so_the_graph_can_filter_before_the_cap
        names = ("A".."U").map { |letter| "Unknown#{letter}" }
        root = project("app/services/caller.rb" => "class Caller\n#{names.map { |name| "  def #{name.downcase} = #{name}\n" }.join}end\n")
        result = Scanner.new(root).scan
        assert_equal 21, names.size
        assert_equal names, result["foreign"].map(&:first)
      end

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

      def test_a_dangling_symlink_is_listed_as_unreadable_and_the_rest_still_scans
        root = project("app/models/order.rb" => "class Order\nend\n")
        File.symlink(File.join(root, "app/models/missing.rb"), File.join(root, "app/models/ghost.rb"))
        result = Scanner.new(root).scan
        assert_equal [["app/models/ghost.rb"], ["Order"]], [result["unreadable"], result["classes"].map { |entry| entry["id"] }]
        assert_empty result["skipped"]
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
    end
  end
end
