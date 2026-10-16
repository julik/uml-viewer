require "json"
require "set"

module Uml
  module Viewer
    module Coverage
      class Unreadable < StandardError; end

      def self.load(root, scanned_files)
        path = File.join(root, "coverage", ".resultset.json")
        return nil unless File.exist?(path)

        resultset = JSON.parse(File.read(path))
        raise Unreadable, "coverage file unreadable: #{path}" unless suites?(resultset)

        parse(resultset, scanned_files)
      rescue JSON::ParserError, SystemCallError
        raise Unreadable, "coverage file unreadable: #{path}"
      end

      def self.suites?(resultset)
        resultset.is_a?(Hash) && resultset.values.all? do |suite|
          suite.is_a?(Hash) && suite["timestamp"].is_a?(Numeric) && suite["coverage"].is_a?(Hash) &&
            suite["coverage"].values.all? { |entry| hits?(entry.is_a?(Hash) ? entry["lines"] : entry) }
        end
      end

      def self.hits?(hits)
        hits.is_a?(Array) && hits.all? { |hit| hit.nil? || hit.is_a?(Integer) }
      end

      def self.parse(resultset, scanned_files)
        wanted = scanned_files.to_set
        lines = {}
        resultset.each_value do |suite|
          root = root_of(suite["coverage"].keys, scanned_files)
          suite["coverage"].each do |absolute, value|
            file = root && absolute.start_with?("#{root}/") ? absolute.delete_prefix("#{root}/") : nil
            next unless wanted.include?(file)

            lines[file] = add(lines[file], value.is_a?(Hash) ? value["lines"] : value)
          end
        end
        { "time" => resultset.values.filter_map { |suite| suite["timestamp"] }.max, "lines" => lines }
      end

      def self.root_of(paths, scanned_files)
        by_name = scanned_files.group_by { |file| File.basename(file) }
        candidates = paths.filter_map do |absolute|
          file = by_name.fetch(File.basename(absolute), []).select { |name| absolute.end_with?("/#{name}") }.max_by(&:size)
          file && absolute.delete_suffix("/#{file}")
        end
        candidates.tally.max_by { |_, count| count }&.first
      end

      def self.add(sum, hits)
        return hits.dup if sum.nil?

        Array.new([sum.size, hits.size].max) do |index|
          left = sum[index]
          right = hits[index]
          left.nil? && right.nil? ? nil : left.to_i + right.to_i
        end
      end
    end
  end
end
