require "json"
require "time"

module Uml
  module Viewer
    class Mailbox
      class QueueFull < StandardError; end

      CAP = 100

      def initialize(workspace)
        @workspace = workspace
      end

      def append(op:, target: nil)
        locked do |state|
          raise QueueFull, "queue full: start Claude or clear the queue" if state["queue"].size >= self.class::CAP

          id = state["next_id"]
          command = { "id" => id, "op" => op }
          command["target"] = target unless target.nil?
          command["at"] = Time.now.utc.iso8601
          state["queue"] << command
          state["next_id"] = id + 1
          id
        end
      end

      def peek
        queue.first
      end

      def queue
        read_state["queue"]
      end

      def size
        queue.size
      end

      def done(id, failed: nil)
        locked do |state|
          command = state["queue"].find { |entry| entry["id"] == id }
          if command
            state["queue"].delete(command)
            log_failure(command, failed) if failed
          end
          command
        end
      end

      def last_failed
        @workspace.read_json("failed.json", []).last
      end

      private

      def read_state
        @workspace.read_json("to-agent.json", { "next_id" => 1, "queue" => [] })
      end

      def locked
        File.open(@workspace.path("to-agent.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          state = read_state
          result = yield(state)
          @workspace.write_atomic("to-agent.json", JSON.generate(state))
          result
        end
      end

      def log_failure(command, reason)
        failures = @workspace.read_json("failed.json", [])
        failures << { "id" => command["id"], "op" => command["op"], "reason" => reason, "at" => Time.now.utc.iso8601 }
        @workspace.write_atomic("failed.json", JSON.generate(failures))
      end
    end
  end
end
