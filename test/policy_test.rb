require "test_helper"

module Uml
  module Viewer
    class PolicyTest < TestCase
      LEVELS = { "levels" => [["models"], ["services"], ["controllers"]] }.freeze

      def scan(classes, edges, namespaces = [])
        {
          "classes" => classes.map { |id, folder| { "id" => id, "kind_folder" => folder, "file" => "x.rb", "files" => ["x.rb"], "stereotype" => "class", "parse_errors" => [] } },
          "edges" => edges.map { |from, to| { "from" => from, "to" => to, "kind" => "dependency" } },
          "namespaces" => namespaces
        }
      end

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
        assert_equal ["folder:models", "folder:services"], graph["boxes"].map { |b| b["id"] }.sort
        arrow = graph["arrows"].first
        assert_equal ["folder:models", "folder:services", true], [arrow["from"], arrow["to"], arrow["violating"]]
      end

      def test_a_namespaced_class_goes_into_the_box_of_its_first_segment_with_child_namespaces_listed
        graph = apply(scan({ "Billing::Gateway::Client" => "services", "Billing::Counter" => "services" }, [], ["Billing", "Billing::Gateway"]))
        box = graph["boxes"].find { |b| b["id"] == "Billing" }
        assert_equal "namespace", box["type"]
        assert_equal [{ "id" => "Billing::Counter", "type" => "class" }, { "id" => "Billing::Gateway", "type" => "namespace" }], box["members"]
      end

      def test_a_class_with_the_id_of_a_namespace_is_a_member_of_that_namespace_box
        graph = apply(scan({ "Payments" => "services", "Payments::Gateway" => "services" }, [], ["Payments"]))
        assert_equal ["Payments"], graph["boxes"].map { |b| b["id"] }
        assert_includes graph["boxes"].first["members"], { "id" => "Payments", "type" => "class" }
      end

      def test_a_box_shows_the_level_range_of_its_classes
        graph = apply(scan({ "Reports::Summary" => "services", "Reports::Page" => "controllers", "Reports::Row" => "models" }, [], ["Reports"]))
        assert_equal [0, 2], graph["boxes"].first["levels"]
      end

      def test_one_violating_edge_makes_the_collapsed_arrow_violating
        classes = { "Order" => "models", "User" => "models", "Pricing" => "services" }
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]), "levels" => [["models", "services"]])
        refute graph["arrows"].first["violating"]
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]))
        assert graph["arrows"].first["violating"]
        assert_equal [["Order", "Pricing"], ["User", "Pricing"]], graph["arrows"].first["pairs"]
      end

      def test_edges_inside_one_box_give_no_arrow
        graph = apply(scan({ "Order" => "models", "User" => "models" }, [["Order", "User"]]))
        assert_empty graph["arrows"]
      end

      def test_omit_removes_the_id_everything_under_it_and_their_edges
        classes = { "Order" => "models", "Reports::Summary" => "services", "Reports::Row" => "services" }
        graph = apply(scan(classes, [["Order", "Reports::Summary"]], ["Reports"]), "omit" => ["Reports"])
        assert_equal ["Order"], graph["classes"].map { |c| c["id"] }
        assert_empty graph["edges"]
        assert_equal ["folder:models"], graph["boxes"].map { |b| b["id"] }
      end

      def test_omit_of_a_kind_box_removes_its_top_level_classes
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "omit" => ["folder:services"])
        assert_equal ["Order"], graph["classes"].map { |c| c["id"] }
      end

      def test_a_top_level_class_with_only_nested_constants_stays_in_its_kind_box
        graph = apply(scan({ "Order" => "models" }, [], ["Order"]))
        assert_equal ["folder:models"], graph["boxes"].map { |b| b["id"] }
        assert_equal [{ "id" => "Order", "type" => "class" }], graph["boxes"].first["members"]
      end

      def test_omit_of_a_kind_box_keeps_a_top_level_class_that_has_nested_classes
        classes = { "Payments" => "services", "Payments::Gateway" => "services", "Pricing" => "services" }
        graph = apply(scan(classes, [], ["Payments"]), "omit" => ["folder:services"])
        assert_equal ["Payments", "Payments::Gateway"], graph["classes"].map { |c| c["id"] }
      end

      def test_a_nested_class_that_is_also_a_child_namespace_is_listed_once_as_the_namespace
        classes = { "Billing::Gateway" => "services", "Billing::Gateway::Client" => "services" }
        graph = apply(scan(classes, [], ["Billing", "Billing::Gateway"]))
        assert_equal [{ "id" => "Billing::Gateway", "type" => "namespace" }], graph["boxes"].first["members"]
      end

      def test_edge_kinds_override_to_association_clears_the_flag_and_the_arrow
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "edge_kinds" => { "Order -> Pricing" => "association" })
        assert_equal ["association", false], [graph["edges"].first["kind"], graph["edges"].first["violating"]]
        refute graph["arrows"].first["violating"]
      end

      def test_edge_kinds_override_to_another_kind_keeps_the_level_check
        graph = apply(scan({ "Order" => "models", "Pricing" => "services" }, [["Order", "Pricing"]]), "edge_kinds" => { "Order -> Pricing" => "inheritance" })
        assert_equal ["inheritance", true], [graph["edges"].first["kind"], graph["edges"].first["violating"]]
      end

      def test_omit_edges_removes_the_pair_from_edges_and_arrow
        classes = { "Order" => "models", "User" => "models", "Pricing" => "services" }
        graph = apply(scan(classes, [["Order", "Pricing"], ["User", "Pricing"]]), "omit_edges" => ["Order -> Pricing"])
        assert_equal [["User", "Pricing"]], graph["edges"].map { |e| [e["from"], e["to"]] }
        assert_equal [["User", "Pricing"]], graph["arrows"].first["pairs"]
      end
    end
  end
end
