require "test_helper"
require "timeout"

module Uml
  module Viewer
    class RescannerTest < TestCase
      def test_a_trigger_during_a_slow_scan_gives_exactly_one_more_scan_with_the_latest_input
        inputs = []
        value = 1
        gate = Queue.new
        rescanner = Rescanner.new(scan: -> { seen = value; gate.pop; inputs << seen })
        rescanner.start
        rescanner.trigger
        sleep 0.1
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
    end
  end
end
