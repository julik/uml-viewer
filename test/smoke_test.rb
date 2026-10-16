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

      def test_a_clean_project_passes_and_prints_counts_and_each_violating_edge
        out = StringIO.new
        project = git_project
        assert_empty Smoke.run([project], out: out)
        assert_match(/\A#{File.basename(project)}: \d+ classes, \d+ violating$/, out.string)
        assert_includes out.string.lines(chomp: true), "  Order -> Reports::Summary (dependency)"
      end

      def test_a_violating_edge_with_two_kinds_prints_both
        project = git_project
        File.write(File.join(project, "app/models/order.rb"), "class Order\n  has_many :summaries, class_name: \"Reports::Summary\"\n  def sum = Reports::Summary.new\nend\n")
        out = StringIO.new
        assert_empty Smoke.run([project], out: out)
        assert_includes out.string.lines(chomp: true), "  Order -> Reports::Summary (association, dependency)"
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

      def test_a_wrong_kind_fails_with_the_found_and_the_expected_kind
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"),
                   YAML.dump([{ "from" => "Order", "to" => "User", "kind" => "dependency", "violating" => false }]))
        assert_equal ["#{File.basename(project)}: Order -> User is association, violating false; expected dependency, violating false"],
                     Smoke.run([project], out: StringIO.new)
      end

      def git_project_named(name)
        project = git_project
        renamed = File.join(File.dirname(project), name)
        File.rename(project, renamed)
        renamed
      end

      def test_two_projects_report_apart
        first = git_project_named("shop_a")
        second = git_project_named("shop_b")
        File.write(Workspace.new(second).path("expect.yml"), YAML.dump([{ "from" => "Order", "to" => "Ghost", "kind" => "dependency", "violating" => false }]))
        out = StringIO.new
        failures = Smoke.run([first, second], out: out)
        assert_equal ["shop_b: missing edge Order -> Ghost (dependency)"], failures
        assert_equal %w[shop_a shop_b], out.string.lines.grep(/: \d+ classes, \d+ violating$/).map { |line| line.split(":").first }
      end

      def test_a_folder_that_does_not_exist_keeps_the_no_such_folder_message
        assert_equal ["shop: no such project folder: /no/such/shop"], Smoke.run(["/no/such/shop"], out: StringIO.new)
      end

      def test_a_scan_that_raises_still_checks_git_status
        project = git_project
        File.write(Workspace.new(project).path("policy.yml"), "levels: [\n")
        failures = Smoke.run([project], out: StringIO.new) { File.write(File.join(project, "stray.txt"), "x") }
        assert_match(/: policy\.yml line \d+: /, failures.first)
        assert_includes failures, "#{File.basename(project)}: git status changed during the scan"
      end

      def test_a_folder_that_is_not_a_git_repository_fails_with_the_reason
        project = project_copy
        assert_equal ["#{File.basename(project)}: not a git repository, so smoke cannot check that git status stays the same"],
                     Smoke.run([project], out: StringIO.new)
      end

      def test_an_empty_expect_file_passes_and_a_non_list_fails
        project = git_project
        File.write(Workspace.new(project).path("expect.yml"), "")
        assert_empty Smoke.run([project], out: StringIO.new)
        File.write(Workspace.new(project).path("expect.yml"), "from: Order\n")
        assert_equal ["#{File.basename(project)}: expect.yml must be a list of edges"], Smoke.run([project], out: StringIO.new)
      end

      def test_the_milestone_record_asks_for_the_facts_that_prove_the_gate
        text = File.read(File.expand_path("../docs/milestone-1.md", __dir__))
        ["Permission mode (must be default)",
         "uml-viewer rules already in ~/.claude/settings*.json or project settings (must be none)",
         "Tool that prompted, if any",
         "Time from right-click Omit to policy.yml",
         'stat -f %Sm "$(uml-viewer path <medium app>)/policy.yml"'].each do |field|
          assert_includes text, field
        end
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
