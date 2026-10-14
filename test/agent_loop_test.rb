require "test_helper"
require "net/http"
require "open3"
require "timeout"

module Uml
  module Viewer
    class AgentLoopTest < TestCase
      EXE = File.expand_path("../exe/uml-viewer", __dir__)

      def test_a_posted_command_reaches_a_piped_watch_within_2_seconds
        project = project_copy
        env = { "UML_VIEWER_HOME" => @home, "UML_VIEWER_NO_BROWSER" => "1" }
        server_in, server_out, server = Open3.popen2e(env, RbConfig.ruby, "-Ilib", EXE, project)
        server_in.close
        workspace = Workspace.new(project)
        Timeout.timeout(15) { sleep 0.1 until workspace.server_alive? }
        info = workspace.server_info
        watch_in, watch_out, watch = Open3.popen2e(env, RbConfig.ruby, "-Ilib", EXE, "watch", project)
        watch_in.close
        sleep 1
        http = Net::HTTP.new("127.0.0.1", info["port"])
        request = Net::HTTP::Post.new("/commands", "X-UML-Token" => info["token"], "Content-Type" => "application/json")
        request.body = JSON.generate("op" => "explain", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => nil })
        started = Time.now
        assert_equal "201", http.request(request).code
        line = Timeout.timeout(2) { watch_out.gets.chomp }
        assert_equal "uml-viewer: command 1 explain Order", line
        assert_operator Time.now - started, :<, 2
      ensure
        [watch, server].compact.each { |thread| Process.kill("INT", thread.pid) if thread.alive? }
        [watch, server].compact.each { |thread| thread.join(5) }
        server_out&.close
        watch_out&.close
      end
    end
  end
end
