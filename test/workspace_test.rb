require "test_helper"

module Uml
  module Viewer
    class WorkspaceTest < TestCase
      def test_state_folder_is_named_after_the_folder_and_the_realpath_hash
        project = Dir.mktmpdir("shop")
        workspace = Workspace.new(project)
        digest = Digest::SHA256.hexdigest(File.realpath(project))[0, 8]
        assert_equal File.join(@home, "projects", "#{File.basename(project)}-#{digest}"), workspace.dir
      end

      def test_a_symlink_and_its_target_share_one_state_folder
        project = Dir.mktmpdir("shop")
        link = File.join(Dir.mktmpdir, "link")
        File.symlink(project, link)
        assert_equal Workspace.new(project).dir, Workspace.new(link).dir
      end

      def test_a_relative_path_with_a_trailing_slash_gives_the_same_state_folder
        project = Dir.mktmpdir("shop")
        relative = Dir.chdir(File.dirname(project)) { Workspace.new("#{File.basename(project)}/").dir }
        assert_equal Workspace.new(project).dir, relative
      end

      def test_the_state_folder_has_mode_0700_and_files_have_mode_0600
        workspace = Workspace.new(Dir.mktmpdir)
        workspace.write_atomic("server.json", "{}")
        assert_equal 0o700, File.stat(workspace.dir).mode & 0o777
        assert_equal 0o600, File.stat(workspace.path("server.json")).mode & 0o777
      end

      def test_write_atomic_leaves_no_temp_file_behind
        workspace = Workspace.new(Dir.mktmpdir)
        workspace.write_atomic("graph.json", "{\"a\":1}")
        assert_equal ["graph.json"], Dir.children(workspace.dir)
        assert_equal({ "a" => 1 }, workspace.read_json("graph.json", nil))
      end

      def test_read_json_returns_the_default_when_the_file_is_missing
        assert_equal({ "queue" => [] }, Workspace.new(Dir.mktmpdir).read_json("to-agent.json", { "queue" => [] }))
      end

      def test_a_relative_uml_viewer_home_is_expanded_against_the_current_folder
        base = Dir.mktmpdir
        ENV["UML_VIEWER_HOME"] = "state"
        home = Dir.chdir(base) { Workspace.home }
        assert_equal File.join(Dir.chdir(base) { Dir.pwd }, "state"), home
      ensure
        FileUtils.rm_rf(base)
      end

      def test_a_missing_project_folder_raises_with_the_path_in_the_message
        error = assert_raises(Workspace::MissingProject) { Workspace.new("/no/such/folder") }
        assert_equal "no such project folder: /no/such/folder", error.message
      end

      def test_server_alive_is_false_without_server_json_and_for_a_dead_pid
        workspace = Workspace.new(Dir.mktmpdir)
        refute workspace.server_alive?
        dead = Process.spawn("true")
        Process.wait(dead)
        workspace.write_atomic("server.json", JSON.generate("pid" => dead, "port" => 1, "token" => "t"))
        refute workspace.server_alive?
      end

      def test_server_alive_is_true_for_the_current_process_with_a_listening_port
        workspace = Workspace.new(Dir.mktmpdir)
        workspace.write_atomic("server.json", JSON.generate("pid" => Process.pid, "port" => open_port, "token" => "t"))
        assert workspace.server_alive?
        assert_equal Process.pid, workspace.server_info["pid"]
      end

      def test_server_alive_is_false_for_a_reused_pid_whose_port_refuses_connections
        workspace = Workspace.new(Dir.mktmpdir)
        workspace.write_atomic("server.json", JSON.generate("pid" => Process.pid, "port" => closed_port, "token" => "t"))
        refute workspace.server_alive?
      end

      def test_server_alive_is_false_for_server_json_that_is_not_an_object
        workspace = Workspace.new(Dir.mktmpdir)
        workspace.write_atomic("server.json", "[1, 2]")
        refute workspace.server_alive?
        workspace.write_atomic("server.json", "\"text\"")
        refute workspace.server_alive?
      end

      def test_server_alive_is_false_for_a_pid_of_zero_or_below
        workspace = Workspace.new(Dir.mktmpdir)
        [0, -1].each do |pid|
          workspace.write_atomic("server.json", JSON.generate("pid" => pid, "port" => open_port, "token" => "t"))
          refute workspace.server_alive?, "pid #{pid} counts as alive"
        end
      end
    end
  end
end
