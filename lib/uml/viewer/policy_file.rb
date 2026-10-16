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

        validate(defaults.merge(data) { |_key, default, given| given.nil? ? default : given })
      rescue Psych::SyntaxError => error
        raise Invalid, "policy.yml line #{error.line}: #{error.problem}"
      rescue Psych::Exception => error
        raise Invalid, "policy.yml: #{error.message}"
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
        unless policy["edge_kinds"].all? { |pair, kind| pair.is_a?(String) && pair.match?(/\A\S+ -> \S+\z/) && Scanner::KINDS.include?(kind) }
          raise Invalid, "policy.yml: edge_kinds maps \"From -> To\" to one of #{Scanner::KINDS.join(', ')}"
        end
        raise Invalid, "policy.yml: title must be text" unless policy["title"].is_a?(String)
        raise Invalid, "policy.yml: proposals must be a list" unless policy["proposals"].is_a?(Array)
        unless policy["proposals"].all? { |proposal| proposal.is_a?(Hash) && !proposal["id"].nil? }
          raise Invalid, "policy.yml: each proposal must be a mapping with an id"
        end
        cutoffs = policy["crap_cutoffs"]
        unless cutoffs.is_a?(Array) && cutoffs.size == 9 && cutoffs.all?(Numeric) && cutoffs.each_cons(2).all? { |low, high| low < high }
          raise Invalid, "policy.yml: crap_cutoffs must be 9 numbers in rising order"
        end

        policy
      end
    end
  end
end
