require "yaml"

module Uml
  module Viewer
    module PolicyFile
      class Invalid < StandardError; end

      DEFAULTS = {
        "title" => "",
        "sources" => %w[app lib],
        "skip" => [],
        "levels" => [],
        "foreign" => [],
        "omit" => [],
        "edge_kinds" => {},
        "omit_edges" => [],
        "crap_cutoffs" => [5, 10, 15, 20, 30, 40, 60, 80, 120],
        "proposals" => []
      }.freeze

      NAME_LISTS = %w[sources skip foreign omit omit_edges].freeze

      def self.load(path)
        defaults = Marshal.load(Marshal.dump(DEFAULTS))
        return defaults unless File.exist?(path)

        data = YAML.safe_load(File.read(path)) || {}
        raise Invalid, "policy.yml: the file must hold a mapping" unless data.is_a?(Hash)

        validate(defaults.merge(data))
      rescue Psych::SyntaxError => error
        raise Invalid, "policy.yml line #{error.line}: #{error.problem}"
      end

      def self.validate(policy)
        NAME_LISTS.each do |key|
          next if policy[key].is_a?(Array) && policy[key].all?(String)

          raise Invalid, "policy.yml: #{key} must be a list of names"
        end
        unless policy["levels"].is_a?(Array) && policy["levels"].all? { |row| row.is_a?(Array) && row.all?(String) }
          raise Invalid, "policy.yml: levels must be a list of lists of folder names"
        end
        raise Invalid, "policy.yml: edge_kinds must be a mapping" unless policy["edge_kinds"].is_a?(Hash)
        raise Invalid, "policy.yml: proposals must be a list" unless policy["proposals"].is_a?(Array)

        policy
      end
    end
  end
end
