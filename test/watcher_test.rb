require "test_helper"
require "open3"
require "timeout"

module Uml
  module Viewer
    class WatcherTest < TestCase
      EXE = File.expand_path("../exe/uml-viewer", __dir__)

      def setup
        super
        @project = project_copy
        @workspace = Workspace.new(@project)
        @mailbox = Mailbox.new(@workspace)
      end

      def fake_server(pid = Process.pid)
        @workspace.write_atomic("server.json", JSON.generate("pid" => pid, "port" => open_port, "token" => "t"))
      end

      def start_watch
        stdin, out, @thread = Open3.popen2e({ "UML_VIEWER_HOME" => @home }, RbConfig.ruby, "-Ilib", EXE, "watch", @project)
        stdin.close
        @out = out
      end

      def next_line(seconds = 3)
        Timeout.timeout(seconds) { @out.gets&.chomp }
      end

      def wait_until_watching
        Timeout.timeout(5, Timeout::Error, "watcher never wrote agent.json") do
          sleep 0.05 until File.exist?(@workspace.path("agent.json"))
        end
      end

      def teardown
        Process.kill("TERM", @thread.pid) if @thread&.alive?
        @thread&.join
        @out&.close
        super
      end

      def test_fifty_queued_commands_give_one_summary_line
        50.times { @mailbox.append(op: "propose") }
        fake_server
        start_watch
        assert_equal "uml-viewer: 50 commands waiting (oldest 1)", next_line
        @mailbox.append(op: "explain", target: { "id" => "Order", "kind" => "class", "proposal_id" => nil })
        assert_equal "uml-viewer: command 51 explain Order", next_line
      end

      def test_an_empty_queue_gives_no_summary_and_a_new_command_is_announced_once
        fake_server
        start_watch
        wait_until_watching
        @mailbox.append(op: "omit", target: { "id" => "folder:models", "kind" => "box", "proposal_id" => nil })
        assert_equal "uml-viewer: command 1 omit folder:models", next_line
        @mailbox.append(op: "propose")
        assert_equal "uml-viewer: command 2 propose", next_line
      end

      def test_exits_when_server_json_disappears
        fake_server
        start_watch
        wait_until_watching
        File.delete(@workspace.path("server.json"))
        assert_equal "uml-viewer: server stopped", next_line
        assert_equal 0, Timeout.timeout(3) { @thread.value.exitstatus }
      end

      def test_exits_when_server_json_names_a_dead_pid
        dead = Process.spawn("true")
        Process.wait(dead)
        fake_server(dead)
        start_watch
        assert_equal "uml-viewer: server stopped", next_line
      end

      def test_writes_a_heartbeat
        fake_server
        start_watch
        wait_until_watching
        assert_in_delta Time.now.to_f, @workspace.read_json("agent.json", {})["heartbeat"], 5
      end

      def test_the_heartbeat_keeps_advancing
        fake_server
        watcher = Thread.new { Watcher.new(@workspace, out: StringIO.new, interval: 0.02, heartbeat: 0.1).run }
        beats = []
        Timeout.timeout(5, Timeout::Error, "heartbeat did not advance twice") do
          until beats.uniq.size >= 3
            beat = @workspace.read_json("agent.json", {})["heartbeat"]
            beats << beat if beat
            sleep 0.02
          end
        end
        assert_operator beats.uniq.size, :>=, 3
      ensure
        watcher&.kill
        watcher&.join
      end

      def test_no_server_within_the_wait_gives_a_message_and_status_1
        out = StringIO.new
        status = Watcher.new(@workspace, out: out, wait_for_server: 0.2).run
        assert_equal 1, status
        assert_equal "uml-viewer: no server for #{@workspace.root}\n", out.string
      end
    end
  end
end
