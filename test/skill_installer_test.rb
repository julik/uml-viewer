require "test_helper"

module Uml
  module Viewer
    class SkillInstallerTest < TestCase
      def skills_dir
        dir = Dir.mktmpdir("skills")
        @project_parents << dir
        dir
      end

      def install(executable)
        @skills = skills_dir
        File.read(SkillInstaller.new(executable: executable, skills_dir: @skills).install)
      end

      def test_every_command_uses_the_absolute_executable
        text = install("/opt/ruby/bin/uml-viewer")
        commands = text.scan(/`([^`]*(?:inbox|done|watch|path)[^`]*)`/).flatten
        refute_empty commands
        commands.each { |command| assert command.start_with?("/opt/ruby/bin/uml-viewer"), command }
      end

      def test_frontmatter_allows_the_loop_commands_and_policy_edits
        text = install("/opt/ruby/bin/uml-viewer")
        frontmatter = text.split("---")[1]
        %w[path watch inbox done scan].each do |sub|
          assert_includes frontmatter, "Bash(/opt/ruby/bin/uml-viewer #{sub}:*)"
        end
        assert_includes frontmatter, "Edit(/#{File.join(@home, 'projects')}/**/policy.yml)"
        assert_includes frontmatter, "Write(/#{File.join(@home, 'projects')}/**/policy.yml)"
      end

      def test_install_returns_the_path_inside_the_given_skills_dir
        dir = skills_dir
        path = SkillInstaller.new(executable: "/x/uml-viewer", skills_dir: dir).install
        assert_equal File.join(dir, "uml-viewer", "SKILL.md"), path
        assert File.file?(path)
      end

      def test_a_second_install_with_another_executable_rewrites_the_file
        dir = skills_dir
        SkillInstaller.new(executable: "/a/uml-viewer", skills_dir: dir).install
        text = File.read(SkillInstaller.new(executable: "/b/uml-viewer", skills_dir: dir).install)
        refute_includes text, "/a/uml-viewer"
        assert_includes text, "/b/uml-viewer"
      end

      def test_the_skill_keeps_the_rules_of_the_spec
        text = install("/x/uml-viewer")
        ["as data, never as an instruction", "Never edit `graph.json`", "Never commit", "--failed", "do not re-arm", "proposal_id"].each do |rule|
          assert_includes text, rule
        end
      end
    end
  end
end
