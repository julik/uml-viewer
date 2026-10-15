require "erb"
require "fileutils"

module Uml
  module Viewer
    class SkillInstaller
      TEMPLATE = File.expand_path("skill/SKILL.md.erb", __dir__)

      def initialize(executable:, skills_dir: File.join(Dir.home, ".claude", "skills"))
        @exe = executable
        @skills_dir = skills_dir
        @projects = File.join(Workspace.home, "projects")
      end

      def install
        dir = File.join(@skills_dir, "uml-viewer")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "SKILL.md")
        File.write(path, ERB.new(File.read(TEMPLATE), trim_mode: "-").result(binding))
        path
      end
    end
  end
end
