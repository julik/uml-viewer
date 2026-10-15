require "open3"
require "yaml"

module Uml
  module Viewer
    module Smoke
      def self.run(paths, out:, &between)
        paths.flat_map do |path|
          name = File.basename(path)
          before = git_status(path)
          workspace = Workspace.new(path)
          Graph.prepare(workspace)
          graph = Graph.build(workspace)
          between&.call
          violating = graph["edges"].count { |edge| edge["violating"] }
          out.puts "#{name}: #{graph['classes'].size} classes, #{violating} violating"
          failures = expectations(workspace, graph).map { |problem| "#{name}: #{problem}" }
          failures << "#{name}: git status changed during the scan" unless git_status(path) == before
          failures
        rescue StandardError => error
          ["#{name}: #{error.message}"]
        end
      end

      def self.git_status(path)
        Open3.capture2("git", "-C", path, "status", "--porcelain").first
      end

      def self.expectations(workspace, graph)
        file = workspace.path("expect.yml")
        return [] unless File.exist?(file)

        YAML.safe_load(File.read(file)).filter_map do |want|
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
