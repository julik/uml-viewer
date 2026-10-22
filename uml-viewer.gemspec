require_relative "lib/uml/viewer/version"

Gem::Specification.new do |spec|
  spec.name = "uml-viewer"
  spec.version = Uml::Viewer::VERSION
  spec.authors = ["Robert Hopman"]
  spec.summary = "A live UML diagram of a Ruby or Rails project in the browser, with a Claude Code agent loop."
  spec.description = "uml-viewer scans a Ruby or Rails project with Prism and shows it as a UML diagram in the browser. " \
                     "Red arrows show dependencies that break the Dependency Rule between Rails layers. Box colors show " \
                     "CRAP from a SimpleCov run. A right-click sends a command to a Claude Code session, which explains " \
                     "the code, changes the policy or writes a proposal. Nothing is written into the viewed project."
  spec.homepage = "https://github.com/roberthopman/uml-viewer"
  spec.licenses = ["MIT", "EPL-2.0"]
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["uml-viewer"]
  spec.add_dependency "prism", ">= 1.9"
  spec.add_dependency "webrick", "~> 1.9"
end
