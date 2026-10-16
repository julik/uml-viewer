require "test_helper"

module Uml
  module Viewer
    class PolicyTest < TestCase
      LEVELS = { "levels" => [["models"], ["services"], ["controllers"]] }.freeze

      def scan(classes, edges, namespaces = [], foreign_edges: [])
        {
          "classes" => classes.map { |id, folder| { "id" => id, "kind_folder" => folder, "file" => "x.rb", "files" => ["x.rb"], "stereotype" => "class", "ops" => [], "parse_errors" => [] } },
          "edges" => edges.map { |from, to, kinds = ["dependency"]| { "from" => from, "to" => to, "kind" => kinds.first, "kinds" => kinds } },
          "foreign_edges" => foreign_edges.map { |from, to| { "from" => from, "to" => to, "kind" => "dependency", "kinds" => ["dependency"] } },
          "namespaces" => namespaces,
          "folders" => classes.values.uniq
        }
      end

      def root_nodes(graph) = graph["views"]["root"]["nodes"]
      def root_arrows(graph) = graph["views"]["root"]["arrows"]

      def apply(scan, policy = {})
        Policy.apply(scan, PolicyFile::DEFAULTS.merge(LEVELS).merge(policy))
      end

      def test_a_model_that_depends_on_a_service_is_violating
        graph = apply(scan({ "Order" => "models", "Reports::Summary" => "services" }, [["Order", "Reports::Summary"]], ["Reports"]))
        assert graph["edges"].first["violating"]
      end

      def test_a_service_that_depends_on_a_model_is_not_violating
        graph = apply(scan({ "Order" => "models", "Reports::Summary" => "services" }, [["Reports::Summary", "Order"]], ["Reports"]))
        refute graph["edges"].first["violating"]
      end

      def test_the_same_level_is_allowed
        graph = apply(scan({ "Order" => "models", "User" => "models" }, [["Order", "User"]]))
        refute graph["edges"].first["violating"]
      end

      def test_an_unlisted_folder_has_no_level_and_is_never_violating
        graph = apply(scan({ "Order" => "models", "Thing" => "workers" }, [["Order", "Thing"]]))
        assert_nil graph["classes"].find { |c| c["id"] == "Thing" }["level"]
        refute graph["edges"].first["violating"]
      end

      def test_top_level_constants_go_into_one_kind_box_per_folder
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]))
        assert_equal ["folder:models", "folder:services"], root_nodes(graph).map { |b| b["id"] }.sort
        arrow = root_arrows(graph).first
        assert_equal ["folder:models", "folder:services", true], [arrow["from"], arrow["to"], arrow["violating"]]
      end

      def test_a_namespaced_class_goes_into_the_box_of_its_first_segment_with_child_namespaces_listed
        graph = apply(scan({ "Billing::Gateway::Client" => "services", "Billing::Counter" => "services" }, [], ["Billing", "Billing::Gateway"]))
        box = root_nodes(graph).find { |b| b["id"] == "Billing" }
        assert_equal "namespace", box["type"]
        assert_equal [{ "id" => "Billing::Counter", "type" => "class", "label" => "Counter" }, { "id" => "Billing::Gateway", "type" => "namespace", "label" => "Gateway" }], box["members"]
      end

      def test_a_class_with_the_id_of_a_namespace_is_a_member_of_that_namespace_box
        graph = apply(scan({ "Payments" => "services", "Payments::Gateway" => "services" }, [], ["Payments"]))
        assert_equal ["Payments"], root_nodes(graph).map { |b| b["id"] }
        assert_includes root_nodes(graph).first["members"], { "id" => "Payments", "type" => "class", "label" => "Payments" }
      end

      def test_a_box_shows_the_level_range_of_its_classes
        graph = apply(scan({ "Reports::Summary" => "services", "Reports::Page" => "controllers", "Reports::Row" => "models" }, [], ["Reports"]))
        assert_equal [0, 2], root_nodes(graph).first["levels"]
      end

      def test_one_violating_edge_makes_the_collapsed_arrow_violating
        classes = { "Order" => "models", "User" => "models", "Pricing" => "services" }
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]), "levels" => [["models", "services"]])
        refute root_arrows(graph).first["violating"]
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]))
        assert root_arrows(graph).first["violating"]
        assert_equal [["Order", "Pricing"], ["User", "Pricing"]], root_arrows(graph).first["pairs"].map { |pair| pair.values_at("from", "to") }
      end

      def test_edges_inside_one_box_give_no_arrow
        graph = apply(scan({ "Order" => "models", "User" => "models" }, [["Order", "User"]]))
        assert_empty root_arrows(graph)
      end

      def test_omit_removes_the_id_everything_under_it_and_their_edges
        classes = { "Order" => "models", "Reports::Summary" => "services", "Reports::Row" => "services" }
        graph = apply(scan(classes, [["Order", "Reports::Summary"]], ["Reports"]), "omit" => ["Reports"])
        assert_equal ["Order"], graph["classes"].map { |c| c["id"] }
        assert_empty graph["edges"]
        assert_equal ["folder:models"], root_nodes(graph).map { |b| b["id"] }
      end

      def test_omit_of_a_kind_box_removes_its_top_level_classes
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "omit" => ["folder:services"])
        assert_equal ["Order"], graph["classes"].map { |c| c["id"] }
      end

      def test_a_top_level_class_with_only_nested_constants_stays_in_its_kind_box
        graph = apply(scan({ "Order" => "models" }, [], ["Order"]))
        assert_equal ["folder:models"], root_nodes(graph).map { |b| b["id"] }
        assert_equal [{ "id" => "Order", "type" => "class", "label" => "Order" }], root_nodes(graph).first["members"]
      end

      def test_omit_of_a_kind_box_keeps_a_top_level_class_that_has_nested_classes
        classes = { "Payments" => "services", "Payments::Gateway" => "services", "Pricing" => "services" }
        graph = apply(scan(classes, [], ["Payments"]), "omit" => ["folder:services"])
        assert_equal ["Payments", "Payments::Gateway"], graph["classes"].map { |c| c["id"] }
      end

      def test_a_nested_class_that_is_also_a_child_namespace_is_listed_once_as_the_namespace
        classes = { "Billing::Gateway" => "services", "Billing::Gateway::Client" => "services" }
        graph = apply(scan(classes, [], ["Billing", "Billing::Gateway"]))
        assert_equal [{ "id" => "Billing::Gateway", "type" => "namespace", "label" => "Gateway" }], root_nodes(graph).first["members"]
      end

      def test_edge_kinds_override_to_association_clears_the_flag_and_the_arrow
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "edge_kinds" => { "Order -> Pricing" => "association" })
        assert_equal ["association", false], [graph["edges"].first["kind"], graph["edges"].first["violating"]]
        refute root_arrows(graph).first["violating"]
      end

      def test_edge_kinds_override_to_another_kind_keeps_the_level_check
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "edge_kinds" => { "Order -> Pricing" => "inheritance" })
        assert_equal ["inheritance", true], [graph["edges"].first["kind"], graph["edges"].first["violating"]]
      end

      def test_omit_edges_removes_the_pair_from_edges_and_arrow
        classes = { "Order" => "models", "User" => "models", "Pricing" => "services" }
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]), "omit_edges" => ["Order -> Pricing"])
        assert_equal [["User", "Pricing"]], graph["edges"].map { |e| [e["from"], e["to"]] }
        assert_equal [["User", "Pricing"]], root_arrows(graph).first["pairs"].map { |pair| pair.values_at("from", "to") }
      end

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

      def test_an_omitted_namespace_leaves_the_namespace_list
        graph = apply(scan({ "Order" => "models", "Reports::Summary" => "services" }, [], ["Reports"]), "omit" => ["Reports"])
        assert_empty graph["namespaces"]
      end

      def test_a_level_folder_that_does_not_exist_on_disk_gives_a_warning
        input = scan({ "Order" => "models" }, []).merge("folders" => %w[lib models])
        graph = apply(input, "levels" => [["models"], ["lib"], ["workers"]])
        assert_equal ["levels: unknown folder workers"], graph["warnings"]
      end
    end
  end
end
