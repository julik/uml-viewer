require "test_helper"

module Uml
  module Viewer
    class GraphTest < TestCase
      def graph
        workspace = Workspace.new(fixture)
        Graph.prepare(workspace)
        Graph.build(workspace)
      end

      def edge(from, to)
        graph["edges"].find { |e| e["from"] == from && e["to"] == to }
      end

      def test_the_first_example_of_the_spec_gives_a_red_dependency_from_order_to_reports_summary
        assert_equal({ "from" => "Order", "to" => "Reports::Summary", "kind" => "dependency", "kinds" => ["dependency"], "violating" => true },
                     edge("Order", "Reports::Summary"))
      end

      def test_reports_summary_to_order_is_not_violating
        refute edge("Reports::Summary", "Order")["violating"]
      end

      def test_a_model_depending_on_a_top_level_service_shows_as_a_red_arrow_between_kind_boxes
        arrow = graph["arrows"].find { |a| a["from"] == "folder:models" && a["to"] == "folder:services" }
        assert arrow["violating"]
        assert_includes arrow["pairs"], ["Order", "Pricing"]
      end

      def test_application_record_is_omitted_by_the_first_policy
        assert_nil graph["classes"].find { |c| c["id"] == "ApplicationRecord" }
      end

      def test_build_writes_graph_json_into_the_state_folder_and_not_into_the_project
        workspace = Workspace.new(fixture)
        before = Dir.glob("**/*", File::FNM_DOTMATCH, base: fixture).sort
        Graph.prepare(workspace)
        Graph.build(workspace)
        assert_equal "rails_shapes", workspace.read_json("graph.json", nil)["title"]
        assert_equal before, Dir.glob("**/*", File::FNM_DOTMATCH, base: fixture).sort
      end

      def test_ids_hold_classes_boxes_and_namespaces
        ids = Graph.ids(graph)
        assert_includes ids, "Order"
        assert_includes ids, "folder:models"
        assert_includes ids, "Reports"
      end

      def test_an_invalid_policy_raises_and_keeps_the_old_graph
        workspace = Workspace.new(fixture)
        Graph.prepare(workspace)
        Graph.build(workspace)
        old = File.read(workspace.path("graph.json"))
        workspace.write_atomic("policy.yml", "levels: [\n")
        assert_raises(PolicyFile::Invalid) { Graph.build(workspace) }
        assert_equal old, File.read(workspace.path("graph.json"))
      end

      def test_a_listed_foreign_name_takes_no_slot_of_the_top_20
        names = ("A".."U").map { |letter| "Unknown#{letter}" }
        root = Dir.mktmpdir("uml-viewer-project")
        @project_parents << root
        FileUtils.mkdir_p(File.join(root, "app/models"))
        calls = names.map { |name| "  def #{name.downcase} = #{name}\n" }.join
        File.write(File.join(root, "app/models/caller.rb"), "class Caller\n  def most = UnknownA\n#{calls}end\n")
        workspace = Workspace.new(root)
        Graph.prepare(workspace)
        assert_equal 20, Graph.build(workspace)["summary"]["foreign"].size
        workspace.write_atomic("policy.yml", File.read(workspace.path("policy.yml")).sub(/^foreign:.*$/, "foreign: [UnknownA]"))
        assert_equal names.drop(1), Graph.build(workspace)["summary"]["foreign"].map(&:first)
      end

      def test_summary_foreign_leaves_out_names_listed_in_the_policy
        workspace = Workspace.new(fixture)
        Graph.prepare(workspace)
        names = Graph.build(workspace)["summary"]["foreign"].map(&:first)
        assert_includes names, "JSON"
        workspace.write_atomic("policy.yml", File.read(workspace.path("policy.yml")).sub(/^foreign:.*$/, "foreign: [JSON]"))
        refute_includes Graph.build(workspace)["summary"]["foreign"].map(&:first), "JSON"
      end
    end
  end
end
