require "test_helper"

module Uml
  module Viewer
    class GemspecTest < Minitest::Test
      SPEC = Gem::Specification.load(File.expand_path("../uml-viewer.gemspec", __dir__))

      def test_the_release_requires_mfa_and_pushes_only_to_rubygems
        assert_equal "true", SPEC.metadata["rubygems_mfa_required"]
        assert_equal "https://rubygems.org", SPEC.metadata["allowed_push_host"]
      end

      def test_the_metadata_links_to_the_source_and_the_changelog
        assert_equal SPEC.homepage, SPEC.metadata["source_code_uri"]
        assert_equal "#{SPEC.homepage}/blob/main/CHANGELOG.md", SPEC.metadata["changelog_uri"]
      end

      def test_the_package_ships_both_licences_and_the_changelog
        assert_includes SPEC.files, "LICENSE"
        assert_includes SPEC.files, "lib/uml/viewer/web/LICENSE-EPL-2.0"
        assert_includes SPEC.files, "CHANGELOG.md"
      end

      def test_the_package_has_a_description
        refute_empty SPEC.description.to_s
      end
    end
  end
end
