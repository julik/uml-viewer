require "test_helper"

module Uml
  module Viewer
    class ProposalsTest < TestCase
      def entry(id, folder, level = nil)
        { "id" => id, "kind_folder" => folder, "level" => level, "stereotype" => "class" }
      end

      def edge(from, to, kind = "dependency")
        { "from" => from, "to" => to, "kind" => kind, "kinds" => [kind], "violating" => false }
      end

      def component(id, members, label: id)
        { "id" => id, "label" => label, "members" => members }
      end

      def proposal(components, omit: [], id: "p1")
        { "id" => id, "name" => "Trial", "components" => components, "omit" => omit }
      end

      def build(proposal, classes, edges = [], namespaces = [], foreign_edges: [])
        Proposals.build([proposal], classes: classes, namespaces: namespaces, edges: edges, foreign_edges: foreign_edges).first
      end

      def all_nodes(views)
        views.values.flat_map { |view| view["nodes"] }
      end

      def red_pairs(views)
        views.values.flat_map { |view| view["arrows"] }.flat_map { |arrow| arrow["pairs"] }
             .select { |pair| pair["violating"] }.map { |pair| [pair["from"], pair["to"]] }
      end

      def parent_box(views, class_id)
        views.find { |_, view| view["nodes"].any? { |node| node["id"] == class_id && node["type"] == "class" } }.first
      end

      CLASSES = [
        ["Shift", "models", 0], ["WeekNumber", "lib", 1], ["ShiftsController", "controllers", 3], ["Employee", "models", 0],
        ["Exports::SheetRenderer", "services", 1], ["Rostering::Corrections::ApprovalsController", "controllers", 3],
        ["Rostering::Corrections::ReviewController", "controllers", 3]
      ].freeze

      def trial
        proposal([component("calendar", ["WeekNumber"]), component("web", ["ShiftsController"]), component("shift", ["Shift"]),
                  component("rostering", ["Rostering"]), component("review", ["Rostering::Corrections::ReviewController"]),
                  component("people", ["Employee"])])
      end

      def test_the_real_example_ranks_edges_by_component_order_and_the_most_specific_member
        edges = [edge("Shift", "WeekNumber"), edge("ShiftsController", "Shift"),
                 edge("Rostering::Corrections::ApprovalsController", "Rostering::Corrections::ReviewController", "inheritance"),
                 edge("Shift", "Employee", "association"), edge("ShiftsController", "Exports::SheetRenderer")]
        views = build(trial, CLASSES.map { |id, folder, level| entry(id, folder, level) }, edges, ["Exports", "Rostering", "Rostering::Corrections"])["views"]
        assert_equal [["ShiftsController", "Shift"], ["Rostering::Corrections::ApprovalsController", "Rostering::Corrections::ReviewController"]].sort,
                     red_pairs(views).sort
        assert_equal "component:p1/review", parent_box(views, "Rostering::Corrections::ReviewController")
        assert_equal ["unassigned:p1", "Exports"], [views["Exports"]["parent"], parent_box(views, "Exports::SheetRenderer")]
      end

      def test_a_class_in_no_component_keeps_its_real_path_inside_unassigned_and_has_no_level
        views = build(proposal([component("core", ["Order"])]), [entry("Order", "models", 0), entry("Billing::Counter", "services", 1)], [], ["Billing"])["views"]
        assert_equal ["component:p1/core", "unassigned:p1"], views["root"]["nodes"].map { |node| node["id"] }
        assert_equal ["Unassigned", nil], views["root"]["nodes"].last.values_at("label", "levels")
        assert_equal ["Billing"], views["unassigned:p1"]["nodes"].map { |node| node["id"] }
        assert_equal ["Billing::Counter"], views["Billing"]["nodes"].map { |node| node["id"] }
      end

      def test_a_namespace_member_keeps_the_namespaces_below_it_as_boxes
        classes = [entry("Billing::Counter", "services"), entry("Billing::Gateway::Client", "services")]
        views = build(proposal([component("money", ["Billing"])]), classes, [], ["Billing", "Billing::Gateway"])["views"]
        assert_equal ["Billing::Counter", "Billing::Gateway"], views["component:p1/money"]["nodes"].map { |node| node["id"] }
        assert_equal ["Billing::Gateway::Client"], views["Billing::Gateway"]["nodes"].map { |node| node["id"] }
      end

      def test_a_folder_member_takes_the_top_level_classes_of_that_folder_only
        classes = [entry("Order", "models"), entry("Shop::Customer", "models")]
        views = build(proposal([component("data", ["folder:models"])]), classes, [], ["Shop"])["views"]
        assert_equal ["Order"], views["component:p1/data"]["nodes"].map { |node| node["id"] }
        assert_equal "Shop", views["unassigned:p1"]["nodes"].first["id"]
      end

      def test_a_nested_component_has_the_rank_of_its_top_level_component
        nested = component("billing", ["Billing::Counter"], label: "Billing")
        views = build(proposal([component("core", ["Order", nested]), component("web", ["OrdersController"])]),
                      [entry("Order", "models"), entry("Billing::Counter", "services"), entry("OrdersController", "controllers")],
                      [edge("Billing::Counter", "OrdersController"), edge("OrdersController", "Billing::Counter")], ["Billing"])["views"]
        assert_equal ["Billing", [0, 0]], all_nodes(views).find { |node| node["id"] == "component:p1/billing" }.values_at("label", "levels")
        assert_equal "component:p1/core", views["component:p1/billing"]["parent"]
        assert_equal [["Billing::Counter", "OrdersController"]], red_pairs(views)
      end

      def test_the_longest_namespace_member_wins_over_a_shorter_one
        classes = [entry("Billing::Counter", "services"), entry("Billing::Gateway::Client", "services")]
        views = build(proposal([component("money", ["Billing"]), component("gateway", ["Billing::Gateway"])]), classes, [], ["Billing", "Billing::Gateway"])["views"]
        assert_equal "component:p1/gateway", parent_box(views, "Billing::Gateway::Client")
        assert_equal "component:p1/money", parent_box(views, "Billing::Counter")
      end

      def test_a_nested_component_under_the_second_component_has_rank_one
        nested = component("billing", ["Billing::Counter"])
        views = build(proposal([component("core", ["Order"]), component("web", ["OrdersController", nested])]),
                      [entry("Order", "models"), entry("Billing::Counter", "services"), entry("OrdersController", "controllers")], [], ["Billing"])["views"]
        assert_equal [1, 1], all_nodes(views).find { |node| node["id"] == "component:p1/billing" }["levels"]
      end

      def test_on_a_tie_the_first_member_in_the_file_wins
        views = build(proposal([component("one", ["Order"]), component("two", ["Order"])]), [entry("Order", "models")])["views"]
        assert_equal "component:p1/one", parent_box(views, "Order")
      end

      def test_the_proposal_omit_removes_classes_by_id_namespace_folder_and_box
        classes = [entry("Order", "models"), entry("User", "models"), entry("Billing::Counter", "services"), entry("Pricing", "services"),
                   entry("Report", "services"), entry("Shop::Customer", "models")]
        omit = ["Order", "Billing", "folder:models", "component:p1/rates"]
        views = build(proposal([component("rates", ["Pricing"])], omit: omit), classes, [], ["Billing", "Shop"])["views"]
        assert_equal ["Report", "Shop::Customer"], all_nodes(views).select { |node| node["type"] == "class" }.map { |node| node["id"] }.sort
      end

      def test_the_proposal_omit_removes_classes_that_sit_in_components_by_id_namespace_and_folder
        classes = [entry("Order", "models"), entry("User", "models"), entry("Billing::Counter", "services"), entry("Keep", "services")]
        components = [component("a", ["Order"]), component("m", ["Billing::Counter"]), component("d", ["User"])]
        views = build(proposal(components, omit: ["Order", "Billing", "folder:models"]), classes, [], ["Billing"])["views"]
        assert_equal ["Keep"], all_nodes(views).select { |node| node["type"] == "class" }.map { |node| node["id"] }
      end

      def test_a_member_listed_in_two_components_that_matches_no_class_gives_one_warning
        result = build(proposal([component("one", ["Ghost"]), component("two", ["Ghost"])]), [entry("Order", "models")])
        assert_equal ["proposal p1: member Ghost matches no class in the diagram (check the name and the policy omit)"], result["warnings"]
      end

      def test_omitting_unassigned_hides_every_class_in_no_component
        views = build(proposal([component("core", ["Order"])], omit: ["unassigned:p1"]), [entry("Order", "models"), entry("User", "models")])["views"]
        assert_equal ["component:p1/core"], views["root"]["nodes"].map { |node| node["id"] }
      end

      def test_an_association_is_never_red_and_an_edge_to_an_omitted_class_leaves
        views = build(proposal([component("a", ["Order"]), component("b", ["User"]), component("c", ["Pricing"])], omit: ["Pricing"]),
                      [entry("Order", "models"), entry("User", "models"), entry("Pricing", "services")],
                      [edge("Order", "User", "association"), edge("Order", "Pricing")])["views"]
        assert_empty red_pairs(views)
        assert_equal [["component:p1/a", "component:p1/b"]], views["root"]["arrows"].map { |arrow| arrow.values_at("from", "to") }
      end

      def test_a_member_that_matches_no_class_gives_a_warning
        result = build(proposal([component("core", ["Order", "Ghost", "folder:jobs"])]), [entry("Order", "models")])
        assert_equal ["proposal p1: member Ghost matches no class in the diagram (check the name and the policy omit)", "proposal p1: member folder:jobs matches no class in the diagram (check the name and the policy omit)"], result["warnings"]
      end

      def test_an_empty_proposal_puts_every_class_into_unassigned
        result = build(proposal([]), [entry("Order", "models")])
        assert_equal ["unassigned:p1"], result["views"]["root"]["nodes"].map { |node| node["id"] }
        assert_equal ["p1", "Trial", []], result.values_at("id", "name", "warnings")
      end

      def test_a_listed_foreign_edge_shows_on_the_proposal_first_screen
        result = build(proposal([component("core", ["Order"])]), [entry("Order", "models")],
                       foreign_edges: [{ "from" => "Order", "to" => "Faraday", "kind" => "dependency", "kinds" => ["dependency"] }])
        assert_includes result["views"]["root"]["nodes"].map { |node| node["id"] }, "foreign:Faraday"
        omitted = build(proposal([component("core", ["Order"])], omit: ["Order"]), [entry("Order", "models")],
                        foreign_edges: [{ "from" => "Order", "to" => "Faraday", "kind" => "dependency", "kinds" => ["dependency"] }])
        refute_includes omitted["views"]["root"]["nodes"].map { |node| node["id"] }, "foreign:Faraday"
      end
    end
  end
end
