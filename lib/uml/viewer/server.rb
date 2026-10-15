require "json"
require "openssl"
require "securerandom"
require "time"
require "webrick"

module Uml
  module Viewer
    class Server
      WEB = File.expand_path("web", __dir__)
      STATIC = { "/app.js" => "app.js", "/elk.js" => "elk.bundled.js" }.freeze
      MAX_BODY = 4096
      EXPIRED = { "error" => "session expired: reopen with uml-viewer" }.freeze

      attr_reader :token

      def initialize(workspace, token: SecureRandom.hex(16), poll: 2)
        @workspace = workspace
        @token = token
        @poll = poll
        @mailbox = Mailbox.new(workspace)
        @rescanner = Rescanner.new(scan: lambda {
          Graph.prepare(workspace)
          Graph.build(workspace)
        })
      end

      def start
        @http = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0,
                                        Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
        servlet = WEBrick::HTTPServlet::ProcHandler.new(method(:route))
        def servlet.service(req, res) = @proc.call(req, res)
        @http.mount("/", servlet)
        @workspace.write_atomic("server.json", JSON.generate("port" => port, "pid" => Process.pid,
                                                             "started_at" => Time.now.utc.iso8601, "token" => @token))
        @rescanner.start
        Thread.new { watch_policy }
        self
      end

      def port
        @http.listeners.first.addr[1]
      end

      def url
        "http://127.0.0.1:#{port}/?token=#{@token}"
      end

      def run
        @http.start
      end

      def shutdown
        @stopping = true
        @rescanner.stop
        @http&.shutdown
        FileUtils.rm_f(@workspace.path("server.json"))
      end

      private

      def route(req, res)
        return respond(res, 403, "error" => "foreign host") unless local_host?(req["Host"])
        return static(res, STATIC[req.path]) if req.request_method == "GET" && STATIC.key?(req.path)
        return page(req, res) if req.request_method == "GET" && req.path == "/"
        return respond(res, 403, EXPIRED) unless token?(req["X-UML-Token"])

        case [req.request_method, req.path]
        when ["GET", "/graph.json"] then raw(res, 200, File.read(@workspace.path("graph.json")))
        when ["GET", "/version"] then respond(res, 200, version)
        when ["POST", "/commands"] then create_command(req, res)
        when ["POST", "/scans"]
          @rescanner.trigger
          respond(res, 202, "scan" => "queued")
        else respond(res, 404, "error" => "not found")
        end
      end

      def token?(given)
        OpenSSL.secure_compare(given.to_s, @token)
      end

      def local_host?(host)
        ["127.0.0.1:#{port}", "localhost:#{port}"].include?(host)
      end

      def page(req, res)
        return respond(res, 403, EXPIRED) unless token?(req.query["token"])

        res.status = 200
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = File.read(File.join(WEB, "index.html"))
      end

      def static(res, file)
        res.status = 200
        res["Content-Type"] = "application/javascript"
        res.body = File.read(File.join(WEB, file))
      end

      def create_command(req, res)
        return respond(res, 413, "error" => "too large") if req["Content-Length"].to_i > MAX_BODY

        text = read_capped(req)
        return respond(res, 413, "error" => "too large") if text.bytesize > MAX_BODY

        body = JSON.parse(text)
        graph = JSON.parse(File.read(@workspace.path("graph.json")))
        proposal_ids = graph["proposals"].map { |proposal| proposal["id"] }
        op, target, reason = Commands.validate(body, ids: Graph.ids(graph), proposal_ids: proposal_ids)
        return respond(res, 400, "error" => reason) if reason

        respond(res, 201, "id" => @mailbox.append(op: op, target: target))
      rescue JSON::ParserError
        respond(res, 400, "error" => "body is not JSON")
      rescue Mailbox::QueueFull => full
        respond(res, 429, "error" => full.message)
      end

      def read_capped(req)
        text = +""
        req.body { |chunk| text << chunk if text.bytesize <= MAX_BODY }
        text
      end

      def version
        {
          "graph" => File.mtime(@workspace.path("graph.json")).to_f,
          "agent" => @workspace.read_json("agent.json", {})["heartbeat"],
          "queue" => @mailbox.size,
          "error" => @rescanner.error,
          "failed" => @mailbox.last_failed
        }
      end

      def watch_policy
        last = policy_mtime
        until @stopping
          sleep @poll
          current = policy_mtime
          next if current == last

          last = current
          @rescanner.trigger
        end
      end

      def policy_mtime
        File.mtime(@workspace.path("policy.yml")).to_f
      rescue Errno::ENOENT
        nil
      end

      def respond(res, status, body)
        raw(res, status, JSON.generate(body))
      end

      def raw(res, status, text)
        res.status = status
        res["Content-Type"] = "application/json"
        res.body = text
      end
    end
  end
end
