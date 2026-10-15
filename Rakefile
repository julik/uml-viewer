require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/fixtures/**/*")
end

task default: :test

desc "Scan each project in UML_VIEWER_SMOKE (paths separated by :) and check expect.yml"
task :smoke do
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "uml/viewer"
  paths = ENV.fetch("UML_VIEWER_SMOKE", "").split(":").reject(&:empty?)
  abort "set UML_VIEWER_SMOKE to one or more project paths separated by :" if paths.empty?
  failures = Uml::Viewer::Smoke.run(paths, out: $stdout)
  abort failures.join("\n") unless failures.empty?
end
