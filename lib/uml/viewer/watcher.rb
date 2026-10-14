require "json"

module Uml
  module Viewer
    class Watcher
      def initialize(workspace, out: $stdout, interval: 0.5, heartbeat: 5, wait_for_server: 30)
        @workspace = workspace
        @out = out
        @interval = interval
        @heartbeat = heartbeat
        @wait_for_server = wait_for_server
        @mailbox = Mailbox.new(workspace)
      end

      def run
        @out.sync = true
        return no_server unless wait_for_server

        queue = @mailbox.queue
        @out.puts "uml-viewer: #{queue.size} commands waiting (oldest #{queue.first['id']})" unless queue.empty?
        last_seen = queue.map { |command| command["id"] }.max || 0
        last_beat = 0.0
        loop do
          return stopped unless @workspace.server_alive?

          if Time.now.to_f - last_beat >= @heartbeat
            @workspace.write_atomic("agent.json", JSON.generate("heartbeat" => Time.now.to_f))
            last_beat = Time.now.to_f
          end
          @mailbox.queue.select { |command| command["id"] > last_seen }.each do |command|
            @out.puts announce(command)
            last_seen = command["id"]
          end
          sleep @interval
        end
      end

      private

      def wait_for_server
        deadline = Time.now + @wait_for_server
        until File.exist?(@workspace.path("server.json"))
          return false if Time.now >= deadline

          sleep 0.1
        end
        true
      end

      def announce(command)
        label = command.dig("target", "id")
        ["uml-viewer: command #{command['id']} #{command['op']}", label].compact.join(" ")
      end

      def no_server
        @out.puts "uml-viewer: no server for #{@workspace.root}"
        1
      end

      def stopped
        @out.puts "uml-viewer: server stopped"
        0
      end
    end
  end
end
