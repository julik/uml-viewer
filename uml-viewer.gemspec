require_relative "lib/uml/viewer/version"

Gem::Specification.new do |spec|
  spec.name = "uml-viewer"
  spec.version = Uml::Viewer::VERSION
  spec.authors = ["Robert Hopman"]
  spec.summary = "A live UML diagram of a Ruby or Rails project in the browser, with a Claude Code agent loop."
  spec.homepage = "https://github.com/roberthopman/uml-viewer"
  spec.licenses = ["MIT", "EPL-2.0"]
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["uml-viewer"]
  spec.add_dependency "prism", ">= 1.9"
  spec.add_dependency "webrick", ">= 1.9"
end
