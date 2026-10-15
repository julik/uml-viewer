require "test_helper"
require "net/http"
require "open3"
require "timeout"

module Uml
  module Viewer
    class AgentLoopTest < TestCase
      EXE = File.expand_path("../exe/uml-viewer", __dir__)

      def capture(stream)
        log = +""
        Thread.new { stream.each_line { |line| log << line } }
        log
      end

      def wait_until(description, log)
        Timeout.timeout(15) { sleep 0.05 until yield }
      rescue Timeout::Error
        flunk "#{description}; output: #{log}"
      end

      def test_a_posted_command_reaches_a_piped_watch_within_2_seconds
        project = project_copy
        env = { "UML_VIEWER_HOME" => @home, "UML_VIEWER_NO_BROWSER" => "1" }
        server_in, server_out, server = Open3.popen2e(env, RbConfig.ruby, "-Ilib", EXE, project)
        server_in.close
        server_log = capture(server_out)
        workspace = Workspace.new(project)
        wait_until("server never started", server_log) { workspace.server_alive? }
        info = workspace.server_info
        watch_in, watch_out, watch = Open3.popen2e(env, RbConfig.ruby, "-Ilib", EXE, "watch", project)
        watch_in.close
        watch_lines = Queue.new
        watch_log = +""
        Thread.new { watch_out.each_line { |line| watch_log << line; watch_lines << line.chomp } }
        wait_until("watch never wrote agent.json", watch_log) { File.exist?(workspace.path("agent.json")) }
        http = Net::HTTP.new("127.0.0.1", info["port"])
        request = Net::HTTP::Post.new("/commands", "X-UML-Token" => info["token"], "Content-Type" => "application/json")
        request.body = JSON.generate("op" => "explain", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => nil })
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        assert_equal "201", http.request(request).code
        line = watch_lines.pop(timeout: 2)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_equal "uml-viewer: command 1 explain Order", line, "watch output: #{watch_log}; server output: #{server_log}"
        assert_operator elapsed, :<, 2
        Process.kill("INT", server.pid)
        assert_equal 0, Timeout.timeout(5) { server.value.exitstatus }
        refute File.exist?(workspace.path("server.json")), "server.json is still there after the server exited"
      ensure
        [watch, server].compact.each { |thread| Process.kill("INT", thread.pid) if thread.alive? }
        [watch, server].compact.each { |thread| thread.join(5) }
        server_out&.close
        watch_out&.close
      end
    end
  end
end
