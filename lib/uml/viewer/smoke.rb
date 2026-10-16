require "open3"
require "yaml"

module Uml
  module Viewer
    module Smoke
      def self.run(paths, out:, &between)
        paths.flat_map do |path|
          name = File.basename(path)
          next ["#{name}: no such project folder: #{path}"] unless File.directory?(path)

          before, repository = git_status(path)
          next ["#{name}: not a git repository, so smoke cannot check that git status stays the same"] unless repository

          failures = check(path, name, out, between)
          failures << "#{name}: git status changed during the scan" unless git_status(path).first == before
          failures
        end
      end

      def self.check(path, name, out, between)
        workspace = Workspace.new(path)
        Graph.prepare(workspace)
        graph = Graph.build(workspace)
        violating = graph["edges"].select { |edge| edge["violating"] }
        out.puts "#{name}: #{graph['classes'].size} classes, #{violating.size} violating"
        violating.each { |edge| out.puts "  #{edge['from']} -> #{edge['to']} (#{edge['kinds'].join(', ')})" }
        expectations(workspace, graph).map { |problem| "#{name}: #{problem}" }
      rescue StandardError => error
        ["#{name}: #{error.message}"]
      ensure
        between&.call
      end

      def self.git_status(path)
        text, status = Open3.capture2e("git", "--no-optional-locks", "-C", path, "status", "--porcelain")
        [text, status.success?]
      end

      def self.expectations(workspace, graph)
        file = workspace.path("expect.yml")
        return [] unless File.exist?(file)

        wants = YAML.safe_load(File.read(file))
        return [] if wants.nil?
        return ["expect.yml must be a list of edges"] unless wants.is_a?(Array) && wants.all?(Hash)

        wants.filter_map do |want|
          found = graph["edges"].find { |edge| edge["from"] == want["from"] && edge["to"] == want["to"] }
          if found.nil?
            "missing edge #{want['from']} -> #{want['to']} (#{want['kind']})"
          elsif found["kind"] != want["kind"] || found["violating"] != want["violating"]
            "#{want['from']} -> #{want['to']} is #{found['kind']}, violating #{found['violating']}; " \
              "expected #{want['kind']}, violating #{want['violating']}"
          end
        end
      end
    end
  end
end
