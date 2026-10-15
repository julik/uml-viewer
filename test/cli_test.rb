require "test_helper"
require "stringio"
require "timeout"

module Uml
  module Viewer
    class CLITest < TestCase
      EXE = File.expand_path("../exe/uml-viewer", __dir__)

      def spawn_exe(*args)
        Process.spawn({ "UML_VIEWER_HOME" => @home, "UML_VIEWER_NO_BROWSER" => "1" }, RbConfig.ruby, "-Ilib", EXE, *args, out: File::NULL)
      end

      def assert_interrupt_exits_cleanly(child, workspace)
        Process.kill("INT", child)
        _, status = Timeout.timeout(5) { Process.wait2(child) }
        assert_equal 0, status.exitstatus
        refute File.exist?(workspace.path("server.json")), "server.json is still there after the process exited"
      end

      def stop_child(child)
        return unless child

        Process.kill("INT", child)
        Process.wait(child)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def run_cli(*argv)
        out = StringIO.new
        err = StringIO.new
        status = CLI.new(argv, out: out, err: err).run
        [status, out.string, err.string]
      end

      def setup
        super
        @project = project_copy
        ENV["UML_VIEWER_NO_BROWSER"] = "1"
      end

      def teardown
        ENV.delete("UML_VIEWER_NO_BROWSER")
        super
      end

      def test_path_prints_the_state_folder
        assert_equal [0, "#{Workspace.new(@project).dir}\n", ""], run_cli("path", @project)
      end

      def test_a_missing_project_folder_prints_the_message_and_returns_1
        assert_equal [1, "", "no such project folder: /no/such\n"], run_cli("scan", "/no/such")
      end

      def test_scan_writes_the_graph_and_prints_a_summary
        status, out, = run_cli("scan", @project)
        assert_equal 0, status
        assert_match(/\A\d+ classes, \d+ edges, \d+ violating, skipped 1 files, no constant\n/, out)
        assert File.exist?(Workspace.new(@project).path("graph.json"))
      end

      def test_scan_with_a_broken_policy_prints_the_line_and_returns_1
        run_cli("init", @project)
        Workspace.new(@project).write_atomic("policy.yml", "levels: [\n")
        status, _, err = run_cli("scan", @project)
        assert_equal 1, status
        assert_match(/\Apolicy\.yml line \d+: /, err)
      end

      def test_inbox_prints_the_oldest_command_and_nothing_when_empty
        assert_equal [0, "", ""], run_cli("inbox", @project)
        Mailbox.new(Workspace.new(@project)).append(op: "propose")
        status, out, = run_cli("inbox", @project)
        assert_equal [0, "propose"], [status, JSON.parse(out)["op"]]
      end

      def test_done_removes_and_done_failed_logs
        mailbox = Mailbox.new(Workspace.new(@project))
        first = mailbox.append(op: "propose")
        second = mailbox.append(op: "propose")
        run_cli("done", first.to_s, @project)
        run_cli("done", second.to_s, @project, "--failed", "target gone")
        assert_equal 0, mailbox.size
        assert_equal "target gone", mailbox.last_failed["reason"]
      end

      def test_init_writes_the_policy_once
        assert_equal 0, run_cli("init", @project).first
        assert_equal [0, "policy.yml exists: #{Workspace.new(@project).path('policy.yml')}\n", ""], run_cli("init", @project)
      end

      def test_a_second_start_with_a_live_server_prints_the_url_and_exits
        workspace = Workspace.new(@project)
        workspace.write_atomic("server.json", JSON.generate("pid" => Process.pid, "port" => 4567, "token" => "abc"))
        assert_equal [0, "already running at http://127.0.0.1:4567/?token=abc\n", ""], run_cli(@project)
      end

      def test_a_stale_server_json_is_replaced_by_a_normal_start
        workspace = Workspace.new(@project)
        dead = Process.spawn("true")
        Process.wait(dead)
        workspace.write_atomic("server.json", JSON.generate("pid" => dead, "port" => 4567, "token" => "abc"))
        child = spawn_exe(@project)
        Timeout.timeout(15) { sleep 0.1 until workspace.server_info && workspace.server_info["pid"] == child }
        refute_equal 4567, workspace.server_info["port"]
        assert_interrupt_exits_cleanly(child, workspace)
      ensure
        stop_child(child)
      end

      def test_ctrl_c_always_removes_server_json_before_the_process_exits
        workspace = Workspace.new(@project)
        8.times do
          child = spawn_exe(@project)
          Timeout.timeout(15) { sleep 0.05 until workspace.server_alive? }
          assert_interrupt_exits_cleanly(child, workspace)
        end
      end

      def test_ctrl_c_on_watch_exits_130_without_a_backtrace
        workspace = Workspace.new(@project)
        workspace.write_atomic("server.json", JSON.generate("pid" => Process.pid, "port" => 1, "token" => "t"))
        reader, writer = IO.pipe
        child = Process.spawn({ "UML_VIEWER_HOME" => @home }, RbConfig.ruby, "-Ilib", EXE, "watch", @project, out: writer, err: writer)
        writer.close
        Timeout.timeout(15) { sleep 0.05 until File.exist?(workspace.path("agent.json")) }
        Process.kill("INT", child)
        _, status = Timeout.timeout(5) { Process.wait2(child) }
        output = reader.read
        assert_equal [130, ""], [status.exitstatus, output]
      ensure
        reader&.close
        stop_child(child)
      end

      def test_done_without_an_id_prints_usage_and_returns_2
        status, _, err = run_cli("done")
        assert_equal 2, status
        assert_includes err, "usage: uml-viewer"
      end

      def test_done_with_a_non_numeric_id_prints_usage_and_returns_2
        status, _, err = run_cli("done", "abc", @project)
        assert_equal 2, status
        assert_includes err, "usage: uml-viewer"
      end

      def test_done_reads_the_id_as_decimal_so_010_is_id_10
        mailbox = Mailbox.new(Workspace.new(@project))
        10.times { mailbox.append(op: "propose") }
        assert_equal 0, run_cli("done", "010", @project).first
        assert_equal [1, 2, 3, 4, 5, 6, 7, 8, 9], mailbox.queue.map { |command| command["id"] }
      end

      def test_install_skill_writes_into_the_home_skills_dir_and_prints_the_rules
        fake_home = Dir.mktmpdir("fake-home")
        @project_parents << fake_home
        original_home = ENV["HOME"]
        ENV["HOME"] = fake_home
        status, out, = run_cli("install-skill")
        skill = File.join(fake_home, ".claude", "skills", "uml-viewer", "SKILL.md")
        assert_equal 0, status
        assert File.file?(skill)
        lines = out.lines.map(&:chomp)
        assert_equal "wrote #{skill}", lines.first
        subcommands = lines[1..5].map { |line| line[/\A  Bash\(\S+ (\w+):\*\)\z/, 1] }
        assert_equal %w[path watch inbox done scan], subcommands
        assert_includes lines, "  Edit(/#{File.join(@home, 'projects')}/**/policy.yml)"
        assert_includes lines, "  Write(/#{File.join(@home, 'projects')}/**/policy.yml)"
        assert_includes lines, "  Read(/#{File.join(@home, 'projects')}/**)"
        assert_equal 9, lines.size
      ensure
        ENV["HOME"] = original_home
      end

      def test_done_with_an_unknown_option_prints_usage_and_returns_2
        status, _, err = run_cli("done", "1", "--bogus")
        assert_equal 2, status
        assert_includes err, "usage: uml-viewer"
      end

      def test_done_with_an_id_that_is_not_queued_names_the_id_and_returns_1
        status, out, err = run_cli("done", "7", @project)
        assert_equal [1, "", "no command with id 7\n"], [status, out, err]
      end

      def test_an_argument_error_inside_scan_surfaces_instead_of_printing_usage
        original = Graph.method(:build)
        Graph.singleton_class.remove_method(:build)
        Graph.define_singleton_method(:build) { |_workspace| raise ArgumentError, "boom" }
        error = assert_raises(ArgumentError) { run_cli("scan", @project) }
        assert_equal "boom", error.message
      ensure
        Graph.singleton_class.remove_method(:build)
        Graph.define_singleton_method(:build, original)
      end
    end
  end
end
