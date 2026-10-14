require "test_helper"
require "timeout"

module Uml
  module Viewer
    class RescannerTest < TestCase
      def test_a_trigger_during_a_slow_scan_gives_exactly_one_more_scan_with_the_latest_input
        inputs = []
        value = 1
        gate = Queue.new
        started = Queue.new
        rescanner = Rescanner.new(scan: -> { seen = value; started << seen; gate.pop; inputs << seen })
        rescanner.start
        rescanner.trigger
        assert_equal 1, started.pop(timeout: 2), "the first scan never started"
        value = 2
        rescanner.trigger
        rescanner.trigger
        3.times { gate << :go }
        Timeout.timeout(2, Timeout::Error, "the rescanner never finished a second scan") { sleep 0.05 until rescanner.scans == 2 }
        sleep 0.2
        assert_equal [1, 2], inputs
        assert_equal 2, rescanner.scans
      ensure
        rescanner&.stop
      end

      def test_a_failing_scan_records_the_error_and_a_later_good_scan_clears_it
        fail_next = true
        rescanner = Rescanner.new(scan: -> { raise PolicyFile::Invalid, "policy.yml line 2: broken" if fail_next })
        rescanner.start
        rescanner.trigger
        Timeout.timeout(2, Timeout::Error, "the failing scan never recorded an error") { sleep 0.05 until rescanner.error }
        assert_equal "policy.yml line 2: broken", rescanner.error
        fail_next = false
        rescanner.trigger
        Timeout.timeout(2, Timeout::Error, "the good scan never cleared the error") { sleep 0.05 until rescanner.error.nil? }
      ensure
        rescanner&.stop
      end

      def test_a_stack_overflow_in_a_scan_is_recorded_and_the_worker_keeps_scanning
        overflow_next = true
        rescanner = Rescanner.new(scan: -> { raise SystemStackError, "stack level too deep" if overflow_next })
        rescanner.start
        rescanner.trigger
        Timeout.timeout(2, Timeout::Error, "the stack overflow was never recorded as the error") { sleep 0.05 until rescanner.error }
        assert_equal "stack level too deep", rescanner.error
        overflow_next = false
        rescanner.trigger
        Timeout.timeout(2, Timeout::Error, "the worker never ran a scan after the stack overflow") { sleep 0.05 until rescanner.scans == 2 }
        assert_nil rescanner.error
      ensure
        rescanner&.stop
      end
    end
  end
end
