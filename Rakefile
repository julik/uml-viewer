require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/fixtures/**/*")
end

task default: :test

Rake::Task["release"].enhance(["test"])

desc "Scan each project in UML_VIEWER_SMOKE (paths separated by :) and check expect.yml"
task :smoke do
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "uml/viewer"
  paths = ENV.fetch("UML_VIEWER_SMOKE", "").split(":").reject(&:empty?)
  abort "set UML_VIEWER_SMOKE to one or more project paths separated by :" if paths.empty?
  failures = Uml::Viewer::Smoke.run(paths, out: $stdout)
  abort failures.join("\n") unless failures.empty?
end

desc "Run the skill with claude -p on a copy of the fixture project (manual; needs a logged-in claude; EVAL_MODEL, EVAL_BUDGET, EVAL_TIMEOUT)"
task "eval:skill" do
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "tmpdir"
  require_relative "eval/skill_eval"
  begin
    timeout = Uml::Viewer::SkillEval.timeout_from(ENV.fetch("EVAL_TIMEOUT", "600"))
  rescue Uml::Viewer::SkillEval::RunnerError => error
    abort error.message
  end
  runner = Uml::Viewer::SkillEval::ClaudeRunner.new(model: ENV.fetch("EVAL_MODEL", "sonnet"), budget: ENV.fetch("EVAL_BUDGET", "1"), timeout: timeout)
  failures = Dir.mktmpdir("uml-viewer-eval") { |dir| Uml::Viewer::SkillEval.new(dir: dir, runner: runner, out: $stdout).run }
  abort failures.join("\n") unless failures.empty?
end
