module Uml
  module Viewer
    class Rescanner
      attr_reader :error, :scans

      def initialize(scan:)
        @scan = scan
        @mutex = Mutex.new
        @wake = ConditionVariable.new
        @dirty = false
        @running = false
        @scans = 0
        @error = nil
      end

      def start
        @running = true
        @thread = Thread.new { work }
        self
      end

      def trigger
        @mutex.synchronize do
          @dirty = true
          @wake.signal
        end
      end

      def stop
        @mutex.synchronize do
          @running = false
          @wake.signal
        end
        @thread&.join(2)
      end

      private

      def work
        loop do
          @mutex.synchronize do
            @wake.wait(@mutex) while @running && !@dirty
            return unless @running

            @dirty = false
          end
          run_once
        end
      end

      def run_once
        @scan.call
        @error = nil
      rescue StandardError => failure
        @error = failure.message
      ensure
        @scans += 1
      end
    end
  end
end
