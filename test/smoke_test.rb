require "test_helper"
require "stringio"
require "yaml"

module Uml
  module Viewer
    class SmokeTest < TestCase
      def git_project
        project = project_copy
        system("git", "-C", project, "init", "-q", exception: true)
        system("git", "-C", project, "add", ".", exception: true)
        system("git", "-C", project, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", "init", exception: true)
        project
      end

      def test_a_clean_project_passes_and_prints_counts
        out = StringIO.new
        assert_empty Smoke.run([git_project], out: out)
        assert_match(/rails_shapes|uml-viewer-project/, out.string)
        assert_match(/\d+ classes, \d+ violating/, out.string)
      end

      def test_an_expected_edge_that_exists_passes
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"),
                   YAML.dump([{ "from" => "Order", "to" => "Reports::Summary", "kind" => "dependency", "violating" => true }]))
        assert_empty Smoke.run([project], out: StringIO.new)
      end

      def test_a_missing_edge_and_a_wrong_flag_fail_with_the_edge_in_the_message
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"), YAML.dump([
          { "from" => "Order", "to" => "Ghost", "kind" => "dependency", "violating" => false },
          { "from" => "Reports::Summary", "to" => "Order", "kind" => "dependency", "violating" => true }
        ]))
        failures = Smoke.run([project], out: StringIO.new)
        assert_includes failures, "#{File.basename(project)}: missing edge Order -> Ghost (dependency)"
        assert_includes failures, "#{File.basename(project)}: Reports::Summary -> Order is dependency, violating false; expected dependency, violating true"
      end

      def test_smoke_never_rewrites_the_git_index_of_the_viewed_project
        project = git_project
        File.utime(Time.now - 3600, Time.now - 3600, File.join(project, "app/models/order.rb"))
        index = File.join(project, ".git/index")
        before = Digest::SHA256.file(index).hexdigest
        assert_empty Smoke.run([project], out: StringIO.new)
        assert_equal before, Digest::SHA256.file(index).hexdigest, "smoke rewrote .git/index"
      end

      def test_a_changed_git_status_fails
        project = git_project
        failures = Smoke.run([project], out: StringIO.new) { File.write(File.join(project, "stray.txt"), "x") }
        assert_includes failures, "#{File.basename(project)}: git status changed during the scan"
      end

      def test_a_scan_exception_is_a_failure_not_a_crash
        project = git_project
        File.write(Workspace.new(project).path("policy.yml"), "levels: [\n")
        failures = Smoke.run([project], out: StringIO.new)
        assert_match(/\A#{File.basename(project)}: policy\.yml line \d+: /, failures.first)
      end
    end
  end
end
