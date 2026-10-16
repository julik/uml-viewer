require "test_helper"

module Uml
  module Viewer
    class CoverageTest < TestCase
      FILES = ["app/models/order.rb", "app/services/pricing.rb"].freeze

      def root_with(json)
        root = Dir.mktmpdir("uml-viewer-project")
        @project_parents << root
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", ".resultset.json"), json)
        root
      end

      def test_the_old_format_of_one_suite_maps_absolute_paths_to_scanned_files
        resultset = { "RSpec" => { "coverage" => {
          "/home/ci/build/app/models/order.rb" => [1, 0, nil],
          "/home/ci/build/vendor/gems/tool/lib/tool.rb" => [1]
        }, "timestamp" => 1_714_042_370 } }
        assert_equal({ "time" => 1_714_042_370, "lines" => { "app/models/order.rb" => [1, 0, nil] } }, Coverage.parse(resultset, FILES))
      end

      def test_the_new_format_reads_the_lines_key
        resultset = { "Minitest" => { "coverage" => { "/srv/app/services/pricing.rb" => { "lines" => [nil, 2, 0], "branches" => {} } }, "timestamp" => 10 } }
        assert_equal({ "app/services/pricing.rb" => [nil, 2, 0] }, Coverage.parse(resultset, FILES)["lines"])
      end

      def test_two_suites_add_their_hits_and_the_newest_timestamp_is_the_time
        resultset = {
          "RSpec" => { "coverage" => { "/a/app/models/order.rb" => [1, 0, nil, nil] }, "timestamp" => 100 },
          "Minitest" => { "coverage" => { "/b/app/models/order.rb" => { "lines" => [2, 0, 3, nil] } }, "timestamp" => 200 }
        }
        assert_equal({ "time" => 200, "lines" => { "app/models/order.rb" => [3, 0, 3, nil] } }, Coverage.parse(resultset, FILES))
      end

      def test_the_longest_matching_scanned_path_wins
        files = ["models/order.rb", "app/models/order.rb"]
        resultset = { "RSpec" => { "coverage" => { "/ci/app/models/order.rb" => [1] }, "timestamp" => 1 } }
        assert_equal ["app/models/order.rb"], Coverage.parse(resultset, files)["lines"].keys
      end

      def test_a_path_with_the_same_tail_outside_the_project_root_is_dropped
        resultset = { "RSpec" => { "coverage" => {
          "/ci/app/models/order.rb" => [nil, 0, 0, nil],
          "/ci/app/services/pricing.rb" => [nil, 1, nil],
          "/ci/engines/billing/app/models/order.rb" => [nil, 4, 4, nil],
          "/x/myapp/services/pricing.rb" => [nil, 9, nil]
        }, "timestamp" => 1 } }
        assert_equal({ "app/models/order.rb" => [nil, 0, 0, nil], "app/services/pricing.rb" => [nil, 1, nil] }, Coverage.parse(resultset, FILES)["lines"])
      end

      def test_a_missing_file_gives_nil
        assert_nil Coverage.load(Dir.mktmpdir.tap { |dir| @project_parents << dir }, FILES)
      end

      def test_load_reads_the_inner_timestamp_so_a_touch_of_the_file_changes_nothing
        root = root_with(JSON.generate("RSpec" => { "coverage" => { "/x/app/models/order.rb" => [1] }, "timestamp" => 1_000 }))
        File.utime(Time.now, Time.now, File.join(root, "coverage", ".resultset.json"))
        assert_equal 1_000, Coverage.load(root, FILES)["time"]
      end

      def test_invalid_json_and_a_wrong_shape_raise_with_the_path
        bad_json = root_with("{\"RSpec\": {")
        error = assert_raises(Coverage::Unreadable) { Coverage.load(bad_json, FILES) }
        assert_equal "coverage file unreadable: #{File.join(bad_json, 'coverage', '.resultset.json')}", error.message
        wrong_shape = root_with(JSON.generate("RSpec" => [1, 2]))
        assert_raises(Coverage::Unreadable) { Coverage.load(wrong_shape, FILES) }
      end

      def test_bad_entries_and_a_missing_timestamp_are_unreadable
        [
          { "RSpec" => { "coverage" => { "/x/app/models/order.rb" => nil }, "timestamp" => 1 } },
          { "RSpec" => { "coverage" => { "/x/app/models/order.rb" => "1,0" }, "timestamp" => 1 } },
          { "RSpec" => { "coverage" => { "/x/app/models/order.rb" => [1, "0"] }, "timestamp" => 1 } },
          { "RSpec" => { "coverage" => { "/x/app/models/order.rb" => { "lines" => nil } }, "timestamp" => 1 } },
          { "RSpec" => { "coverage" => { "/x/app/models/order.rb" => [1, 0] } } },
          {}
        ].each do |resultset|
          assert_raises(Coverage::Unreadable, resultset.inspect) { Coverage.load(root_with(JSON.generate(resultset)), FILES) }
        end
      end
    end
  end
end
