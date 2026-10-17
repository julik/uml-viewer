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
        arrow = graph["views"]["root"]["arrows"].find { |a| a["from"] == "folder:models" && a["to"] == "folder:services" }
        assert arrow["violating"]
        assert_includes arrow["pairs"].map { |pair| pair.values_at("from", "to") }, ["Order", "Pricing"]
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

      def test_ids_hold_class_ids_and_box_ids_apart
        ids = Graph.ids(graph)
        assert_includes ids["class"], "Order"
        assert_includes ids["box"], "folder:models"
        assert_includes ids["box"], "Reports"
        refute_includes ids["class"], "folder:models"
      end

      def test_graph_json_is_version_3_with_views_and_no_boxes
        assert_equal [3, true, false], [graph["version"], graph["views"].key?("Reports"), graph.key?("boxes")]
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

      def test_an_unreadable_file_shows_as_a_summary_warning
        project = project_copy
        File.symlink(File.join(project, "app/models/missing.rb"), File.join(project, "app/models/ghost.rb"))
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        assert_includes Graph.build(workspace)["summary"]["warnings"], "unreadable file: app/models/ghost.rb"
      end

      def test_the_summary_counts_associations_and_lists_warnings
        summary = graph["summary"]
        assert_equal [0, 0, []], summary.values_at("unresolved", "polymorphic", "warnings")
      end

      def test_inputs_list_the_policy_and_every_source_file_and_survive_a_dangling_symlink
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        File.symlink(File.join(project, "app/models/missing.rb"), File.join(project, "app/models/ghost.rb"))
        inputs = Graph.inputs(workspace)
        ghost = File.join(workspace.root, "app/models/ghost.rb")
        assert_includes inputs.keys, workspace.path("policy.yml")
        assert_kind_of Float, inputs[File.join(workspace.root, "app/models/order.rb")]
        assert inputs.key?(ghost), "the dangling symlink is not listed"
        assert_nil inputs[ghost]
      end

      def test_inputs_fall_back_to_the_default_sources_when_the_policy_is_invalid
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        workspace.write_atomic("policy.yml", "levels: [\n")
        assert_includes Graph.inputs(workspace).keys, File.join(workspace.root, "app/models/order.rb")
      end

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
        assert_equal 10, services["c_grade"]
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
        refute_equal "coverage file unreadable: #{path}", Graph.build(workspace)["summary"]["coverage"]["banner"]
      end

      def test_a_partial_result_file_shows_the_partial_banner
        project = project_copy
        write_coverage(project, resultset_for(project, { "app/services/pricing.rb" => [nil, 1, 1, nil, nil] }))
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        coverage = Graph.build(workspace)["summary"]["coverage"]
        assert_equal "coverage looks partial: 1 of #{coverage['scanned']} files; run the full suite", coverage["banner"]
      end

      def test_a_mutation_snapshot_gives_m_grades_and_a_broken_one_a_warning
        workspace = Workspace.new(project_copy)
        Graph.prepare(workspace)
        workspace.write_atomic("mutation.json", JSON.generate("Pricing#initialize" => { "killed" => 9, "survived" => 1, "uncovered" => 0 }))
        assert_equal 9, Graph.build(workspace)["classes"].find { |entry| entry["id"] == "Pricing" }["mutation"]["grade"]
        workspace.write_atomic("mutation.json", "[1, 2]")
        assert_includes Graph.build(workspace)["summary"]["warnings"], "mutation snapshot unreadable: #{workspace.path('mutation.json')}"
        [{ "killed" => [] }, { "killed" => true }, { "killed" => 5, "survived" => -3 }].each do |counts|
          workspace.write_atomic("mutation.json", JSON.generate("Pricing#initialize" => counts))
          graph = Graph.build(workspace)
          assert_includes graph["summary"]["warnings"], "mutation snapshot unreadable: #{workspace.path('mutation.json')}", counts.inspect
          assert_nil graph["classes"].find { |entry| entry["id"] == "Pricing" }["mutation"], counts.inspect
        end
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

      def add_proposal(workspace, proposal)
        policy = YAML.safe_load(File.read(workspace.path("policy.yml")))
        policy["proposals"] = [proposal]
        workspace.write_atomic("policy.yml", YAML.dump(policy))
      end

      def test_a_proposal_reaches_the_graph_with_graded_views_and_its_boxes_count_as_targets
        workspace = Workspace.new(project_copy)
        Graph.prepare(workspace)
        add_proposal(workspace, "id" => "p1", "name" => "Trial", "components" => [{ "id" => "core", "members" => ["Reports"] }])
        graph = Graph.build(workspace)
        proposal = graph["proposals"].first
        assert_equal ["p1", "Trial"], proposal.values_at("id", "name")
        core = proposal["views"]["root"]["nodes"].find { |node| node["id"] == "component:p1/core" }
        assert core.key?("c_grade")
        ids = Graph.ids(graph)
        assert_includes ids["proposal_boxes"]["p1"], "component:p1/core"
        assert_includes ids["proposal_boxes"]["p1"], "unassigned:p1"
        refute_includes ids["box"], "component:p1/core"
      end
    end
  end
end
