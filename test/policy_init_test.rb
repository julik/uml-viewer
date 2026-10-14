require "test_helper"

module Uml
  module Viewer
    class PolicyInitTest < TestCase
      def test_folder_kinds_lists_the_app_folders_and_lib_without_skipped_ones
        assert_equal %w[controllers lib models services], PolicyInit.folder_kinds(fixture)
      end

      def test_levels_come_from_the_default_table_filtered_to_existing_kinds
        workspace = Workspace.new(fixture)
        assert PolicyInit.write(workspace, class_ids: ["ApplicationRecord", "ApplicationController", "Order"])
        policy = PolicyFile.load(workspace.path("policy.yml"))
        assert_equal [["models"], ["services", "lib"], ["controllers"]], policy["levels"]
        assert_equal ["ApplicationRecord", "ApplicationController"], policy["omit"]
        assert_equal "rails_shapes", policy["title"]
      end

      def test_an_existing_policy_is_never_overwritten
        workspace = Workspace.new(fixture)
        workspace.write_atomic("policy.yml", "omit: [Mine]\n")
        refute PolicyInit.write(workspace, class_ids: [])
        assert_equal "omit: [Mine]\n", File.read(workspace.path("policy.yml"))
      end

      def test_a_kind_folder_not_in_the_table_is_listed_in_a_comment_under_levels
        project = Dir.mktmpdir("odd")
        FileUtils.mkdir_p(File.join(project, "app", "workers"))
        FileUtils.mkdir_p(File.join(project, "app", "models"))
        workspace = Workspace.new(project)
        PolicyInit.write(workspace, class_ids: [])
        lines = File.read(workspace.path("policy.yml")).lines.map(&:chomp)
        assert_equal "# not compared: workers", lines[lines.index("levels:") + 1]
        assert_equal [["models"]], PolicyFile.load(workspace.path("policy.yml"))["levels"]
      end

      def test_a_project_with_only_unlisted_kinds_keeps_the_comment_under_an_empty_levels
        project = Dir.mktmpdir("odd")
        FileUtils.mkdir_p(File.join(project, "app", "workers"))
        workspace = Workspace.new(project)
        PolicyInit.write(workspace, class_ids: [])
        lines = File.read(workspace.path("policy.yml")).lines.map(&:chomp)
        assert_equal "# not compared: workers", lines[lines.index("levels: []") + 1]
      end

      def test_no_comment_is_written_when_every_kind_is_in_the_table
        workspace = Workspace.new(fixture)
        PolicyInit.write(workspace, class_ids: [])
        refute_includes File.read(workspace.path("policy.yml")), "not compared"
      end

      def test_the_policy_file_has_mode_0600
        workspace = Workspace.new(fixture)
        PolicyInit.write(workspace, class_ids: [])
        assert_equal 0o600, File.stat(workspace.path("policy.yml")).mode & 0o777
      end

      def test_omit_is_a_block_list_when_a_candidate_exists
        workspace = Workspace.new(fixture)
        PolicyInit.write(workspace, class_ids: ["ApplicationRecord"])
        assert_includes File.read(workspace.path("policy.yml")), "omit:\n- ApplicationRecord\n"
      end
    end
  end
end
