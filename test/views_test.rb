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
