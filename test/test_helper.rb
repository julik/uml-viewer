require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "uml/viewer"

module Uml
  module Viewer
    class TestCase < Minitest::Test
      FIXTURES = File.expand_path("fixtures/projects", __dir__)

      def setup
        @home = Dir.mktmpdir("uml-viewer-home")
        ENV["UML_VIEWER_HOME"] = @home
        @project_parents = []
      end

      def teardown
        ENV.delete("UML_VIEWER_HOME")
        FileUtils.rm_rf(@home)
        FileUtils.rm_rf(@project_parents)
      end

      def fixture(name = "rails_shapes")
        File.join(FIXTURES, name)
      end

      def project_copy(name = "rails_shapes")
        parent = Dir.mktmpdir("uml-viewer-project")
        @project_parents << parent
        dir = File.join(parent, name)
        FileUtils.mkdir_p(dir)
        FileUtils.cp_r(File.join(fixture(name), "."), dir)
        dir
      end
    end
  end
end
