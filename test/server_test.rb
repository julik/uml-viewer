require "test_helper"
require "net/http"
require "socket"
require "timeout"

module Uml
  module Viewer
    class ServerTest < TestCase
      def setup
        super
        @project = project_copy
        @workspace = Workspace.new(@project)
        Graph.prepare(@workspace)
        Graph.build(@workspace)
        @server = Server.new(@workspace, poll: 0.2).start
        @thread = Thread.new { @server.run }
      end

      def teardown
        @server.shutdown
        @thread.join(2)
        super
      end

      def request(method, path, body: nil, token: @server.token, host: "127.0.0.1:#{@server.port}")
        http = Net::HTTP.new("127.0.0.1", @server.port)
        klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
        req = klass.new(path)
        req["Host"] = host
        req["X-UML-Token"] = token if token
        req["Content-Type"] = "application/json"
        req.body = body if body
        http.request(req)
      end

      def command(body)
        request(:post, "/commands", body: JSON.generate(body))
      end

      def propose_of_size(bytes)
        json = JSON.generate("op" => "propose")
        json + (" " * (bytes - json.bytesize))
      end

      def chunked_command(*pieces)
        socket = TCPSocket.new("127.0.0.1", @server.port)
        chunks = pieces.map { |piece| "#{piece.bytesize.to_s(16)}\r\n#{piece}\r\n" }.join
        socket.write("POST /commands HTTP/1.1\r\nHost: 127.0.0.1:#{@server.port}\r\nX-UML-Token: #{@server.token}\r\n" \
                     "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n#{chunks}0\r\n\r\n")
        socket.gets.split[1]
      ensure
        socket&.close
      end

      def test_server_json_holds_port_pid_token_and_an_iso8601_start_time_with_mode_0600
        info = @workspace.server_info
        assert_equal [@server.port, Process.pid, @server.token], info.values_at("port", "pid", "token")
        assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, info["started_at"])
        assert_equal 0o600, File.stat(@workspace.path("server.json")).mode & 0o777
      end

      def test_the_url_carries_the_port_and_the_token
        assert_equal "http://127.0.0.1:#{@server.port}/?token=#{@server.token}", @server.url
      end

      def test_the_page_needs_no_token_because_it_holds_no_data
        response = request(:get, "/", token: nil)
        assert_equal ["200", "text/html; charset=utf-8"], [response.code, response["Content-Type"]]
        refute_includes response.body, @server.token
      end

      def test_the_page_refuses_to_be_framed
        response = request(:get, "/", token: nil)
        assert_equal ["DENY", "frame-ancestors 'none'"], [response["X-Frame-Options"], response["Content-Security-Policy"]]
      end

      def test_source_returns_the_text_of_a_scanned_file_with_the_line
        body = JSON.parse(request(:get, "/source?file=app/models/order.rb&line=7").body)
        assert_equal ["app/models/order.rb", 7], body.values_at("file", "line")
        assert_includes body["text"], "def total = Order.sum(:amount)"
      end

      def test_source_refuses_a_path_outside_the_graph
        ["../../etc/passwd", "Gemfile", "app/views/orders/index.html.erb", "lib/scripts/run_once.rb"].each do |path|
          response = request(:get, "/source?file=#{path}&line=1")
          assert_equal ["403", "not a scanned file"], [response.code, JSON.parse(response.body)["error"]], path
        end
      end

      def test_source_needs_the_token
        assert_equal "403", request(:get, "/source?file=app/models/order.rb&line=1", token: nil).code
      end

      def test_source_of_a_file_deleted_since_the_scan_gets_404_with_the_file
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        Graph.build(workspace)
        slow = Server.new(workspace, poll: 60).start
        thread = Thread.new { slow.run }
        File.delete(File.join(project, "app/models/user.rb"))
        http = Net::HTTP.new("127.0.0.1", slow.port)
        req = Net::HTTP::Get.new("/source?file=app/models/user.rb&line=1")
        req["Host"] = "127.0.0.1:#{slow.port}"
        req["X-UML-Token"] = slow.token
        response = http.request(req)
        assert_equal ["404", "file gone: app/models/user.rb"], [response.code, JSON.parse(response.body)["error"]]
      ensure
        slow&.shutdown
        thread&.join(2)
      end

      def test_shutdown_does_not_wait_for_the_poll_interval
        project = project_copy
        workspace = Workspace.new(project)
        Graph.prepare(workspace)
        Graph.build(workspace)
        slow = Server.new(workspace, poll: 5).start
        thread = Thread.new { slow.run }
        sleep 0.3
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        slow.shutdown
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_operator elapsed, :<, 1
      ensure
        thread&.join(2)
      end

      def test_session_starts_empty_and_returns_what_was_stored_with_mode_0600
        assert_equal({}, JSON.parse(request(:get, "/session").body))
        view = { "drill" => ["root", "Reports"], "zoom" => 1.25, "scroll" => { "x" => 0, "y" => 40 }, "proposal" => nil }
        assert_equal "204", request(:put, "/session", body: JSON.generate(view)).code
        assert_equal view, JSON.parse(request(:get, "/session").body)
        assert_equal 0o600, File.stat(@workspace.path("session.json")).mode & 0o777
      end

      def test_a_bad_session_gets_400_with_the_reason
        assert_equal "unknown key: theme", JSON.parse(request(:put, "/session", body: '{"theme":"dark"}').body)["error"]
        assert_equal "drill must be a list of ids", JSON.parse(request(:put, "/session", body: '{"drill":"root"}').body)["error"]
        assert_equal "zoom must be a number", JSON.parse(request(:put, "/session", body: '{"zoom":"big"}').body)["error"]
        assert_equal "scroll must hold x and y numbers", JSON.parse(request(:put, "/session", body: '{"scroll":{"x":1}}').body)["error"]
        assert_equal "proposal must be an id or null", JSON.parse(request(:put, "/session", body: '{"proposal":3}').body)["error"]
        assert_equal "session must be a JSON object", JSON.parse(request(:put, "/session", body: "[1]").body)["error"]
        assert_equal ["400", "body is not JSON"], request(:put, "/session", body: "{").then { |r| [r.code, JSON.parse(r.body)["error"]] }
        assert_equal "413", request(:put, "/session", body: JSON.generate("drill" => ["x" * 5000])).code
      end

      def test_a_new_source_file_rescans_and_a_deleted_one_leaves_the_graph
        path = File.join(@project, "app/models/invoice.rb")
        File.write(path, "class Invoice\nend\n")
        wait_for_graph("the new Invoice class never reached the graph") { |graph| graph["classes"].any? { |entry| entry["id"] == "Invoice" } }
        File.delete(path)
        wait_for_graph("the deleted Invoice class stayed in the graph") { |graph| graph["classes"].none? { |entry| entry["id"] == "Invoice" } }
      end

      def test_an_unreadable_policy_shows_in_version_and_the_poll_goes_on
        File.chmod(0o000, @workspace.path("policy.yml"))
        Timeout.timeout(5, Timeout::Error, "/version never reported the watch error") do
          sleep 0.1 until JSON.parse(request(:get, "/version").body)["error"].to_s.start_with?("cannot watch the project: ")
        end
        File.chmod(0o600, @workspace.path("policy.yml"))
        File.write(File.join(@project, "app/models/invoice.rb"), "class Invoice\nend\n")
        wait_for_graph("the poll stopped after the read error") { |graph| graph["classes"].any? { |entry| entry["id"] == "Invoice" } }
      ensure
        File.chmod(0o600, @workspace.path("policy.yml"))
      end

      def wait_for_graph(message)
        Timeout.timeout(5, Timeout::Error, message) do
          sleep 0.1 until yield(JSON.parse(request(:get, "/graph.json").body))
        end
      end

      def test_static_scripts_need_no_token
        assert_equal "200", request(:get, "/app.js", token: nil).code
        response = request(:get, "/elk.js", token: nil)
        assert_equal ["200", "application/javascript"], [response.code, response["Content-Type"]]
      end

      def test_graph_json_without_or_with_a_wrong_token_is_refused
        assert_equal "403", request(:get, "/graph.json", token: nil).code
        assert_equal "403", request(:get, "/graph.json", token: "wrong").code
        assert_equal "rails_shapes", JSON.parse(request(:get, "/graph.json").body)["title"]
      end

      def test_a_foreign_host_header_is_refused
        assert_equal "403", request(:get, "/graph.json", host: "evil.example:#{@server.port}").code
        assert_equal "200", request(:get, "/graph.json", host: "localhost:#{@server.port}").code
      end

      def test_a_host_header_with_another_port_is_refused
        assert_equal "403", request(:get, "/graph.json", host: "127.0.0.1:#{@server.port + 1}").code
      end

      def test_a_request_without_a_host_header_is_refused
        socket = TCPSocket.new("127.0.0.1", @server.port)
        socket.write("GET /graph.json HTTP/1.0\r\nX-UML-Token: #{@server.token}\r\n\r\n")
        assert_equal "HTTP/1.1 403", socket.gets.to_s[0, 12]
      ensure
        socket&.close
      end

      def test_a_command_without_the_token_is_refused_and_not_queued
        response = request(:post, "/commands", body: JSON.generate("op" => "propose"), token: nil)
        assert_equal "403", response.code
        assert_equal 0, Mailbox.new(@workspace).size
      end

      def test_a_preflight_without_the_token_is_refused_with_no_cors_allow_headers
        http = Net::HTTP.new("127.0.0.1", @server.port)
        preflight = Net::HTTP::Options.new("/commands")
        preflight["Origin"] = "http://evil.example"
        preflight["Access-Control-Request-Method"] = "POST"
        preflight["Access-Control-Request-Headers"] = "x-uml-token"
        response = http.request(preflight)
        assert_equal "403", response.code
        assert_nil response["Access-Control-Allow-Origin"]
        assert_nil response["Access-Control-Allow-Headers"]
        assert_nil response["Allow"]
      end

      def test_a_valid_command_is_queued_with_201_and_its_id
        response = command("op" => "explain", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => nil })
        assert_equal ["201", { "id" => 1 }], [response.code, JSON.parse(response.body)]
        assert_equal "explain", Mailbox.new(@workspace).peek["op"]
      end

      def test_omit_on_a_kind_box_id_is_accepted
        assert_equal "201", command("op" => "omit", "target" => { "id" => "folder:models", "kind" => "box", "proposal_id" => nil }).code
      end

      def test_an_unknown_target_bad_json_and_an_unknown_key_get_400_with_the_reason
        response = command("op" => "omit", "target" => { "id" => "Ghost", "kind" => "class", "proposal_id" => nil })
        assert_equal ["400", "unknown target: Ghost"], [response.code, JSON.parse(response.body)["error"]]
        assert_equal "400", request(:post, "/commands", body: "{not json").code
        assert_equal "unknown key: note", JSON.parse(command("op" => "propose", "note" => 1).body)["error"]
        assert_equal 0, Mailbox.new(@workspace).size
      end

      def test_a_body_over_4_kb_gets_413
        response = request(:post, "/commands", body: JSON.generate("op" => "propose", "pad" => "x" * 5000))
        assert_equal "413", response.code
      end

      def test_a_body_of_exactly_4096_bytes_is_queued_and_4097_bytes_gets_413
        assert_equal "201", request(:post, "/commands", body: propose_of_size(4096)).code
        assert_equal "413", request(:post, "/commands", body: propose_of_size(4097)).code
        assert_equal 1, Mailbox.new(@workspace).size
      end

      def test_a_chunked_body_of_exactly_4096_bytes_is_queued_and_4097_bytes_gets_413
        too_large = propose_of_size(4097)
        assert_equal "201", chunked_command(propose_of_size(4096))
        assert_equal "413", chunked_command(too_large[0, 4096], too_large[4096..])
        assert_equal 1, Mailbox.new(@workspace).size
      end

      def test_a_full_queue_gets_429_with_the_message
        Mailbox::CAP.times { Mailbox.new(@workspace).append(op: "propose") }
        response = command("op" => "propose")
        assert_equal ["429", "queue full: start Claude or clear the queue"], [response.code, JSON.parse(response.body)["error"]]
      end

      def test_version_reports_graph_time_agent_queue_error_and_failed
        Mailbox.new(@workspace).append(op: "propose")
        body = JSON.parse(request(:get, "/version").body)
        assert_equal %w[agent error failed graph queue], body.keys.sort
        assert_equal 1, body["queue"]
        assert_nil body["error"]
      end

      def test_a_failed_command_shows_in_version
        mailbox = Mailbox.new(@workspace)
        mailbox.done(mailbox.append(op: "propose"), failed: "target gone")
        assert_equal "target gone", JSON.parse(request(:get, "/version").body)["failed"]["reason"]
      end

      def test_post_scans_rescans_and_returns_202
        before = File.mtime(@workspace.path("graph.json"))
        sleep 1.1
        assert_equal "202", request(:post, "/scans").code
        Timeout.timeout(3, Timeout::Error, "POST /scans never rewrote graph.json") do
          sleep 0.1 until File.mtime(@workspace.path("graph.json")) > before
        end
      end

      def test_a_policy_change_rescans_and_the_omitted_box_leaves_the_graph
        policy = File.read(@workspace.path("policy.yml")).sub("omit:\n", "omit:\n- Reports\n")
        @workspace.write_atomic("policy.yml", policy)
        Timeout.timeout(5, Timeout::Error, "the graph never dropped the omitted Reports box") do
          sleep 0.1 until JSON.parse(request(:get, "/graph.json").body)["views"]["root"]["nodes"].none? { |box| box["id"] == "Reports" }
        end
      end

      def test_a_broken_policy_keeps_the_old_graph_and_reports_the_error_then_recovers
        good = File.read(@workspace.path("policy.yml"))
        old_graph = request(:get, "/graph.json").body
        @workspace.write_atomic("policy.yml", "levels: [\n")
        Timeout.timeout(5, Timeout::Error, "/version never reported the policy error") do
          sleep 0.1 until JSON.parse(request(:get, "/version").body)["error"]
        end
        assert_match(/\Apolicy\.yml line \d+: /, JSON.parse(request(:get, "/version").body)["error"])
        assert_equal old_graph, request(:get, "/graph.json").body
        @workspace.write_atomic("policy.yml", good)
        Timeout.timeout(5, Timeout::Error, "/version never cleared the error after a good policy") do
          sleep 0.1 until JSON.parse(request(:get, "/version").body)["error"].nil?
        end
      end

      def test_a_rescan_after_policy_yml_was_deleted_writes_the_first_policy_again
        File.delete(@workspace.path("policy.yml"))
        assert_equal "202", request(:post, "/scans").code
        Timeout.timeout(3, Timeout::Error, "the rescan never wrote policy.yml again") do
          sleep 0.1 until File.exist?(@workspace.path("policy.yml"))
        end
        assert_includes File.read(@workspace.path("policy.yml")), "ApplicationRecord"
      end

      def test_shutdown_removes_server_json
        @server.shutdown
        @thread.join(2)
        refute File.exist?(@workspace.path("server.json"))
      end

      def test_a_new_coverage_file_rescans_and_colors_the_graph
        FileUtils.mkdir_p(File.join(@project, "coverage"))
        File.write(File.join(@project, "coverage", ".resultset.json"),
                   JSON.generate("RSpec" => { "coverage" => { File.join(@workspace.root, "app/services/pricing.rb") => [nil, 1, 1, nil, nil] }, "timestamp" => Time.now.to_i + 60 }))
        wait_for_graph("the coverage file never reached the graph") do |graph|
          graph["classes"].find { |entry| entry["id"] == "Pricing" }["crap"]
        end
      end
    end
  end
end
