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
        policy["proposals"] = proposals(policy["proposals"])
        cutoffs = policy["crap_cutoffs"]
        unless cutoffs.is_a?(Array) && cutoffs.size == 9 && cutoffs.all?(Numeric) && cutoffs.each_cons(2).all? { |low, high| low < high }
          raise Invalid, "policy.yml: crap_cutoffs must be 9 numbers in rising order"
        end

        policy
      end

      def self.proposals(list)
        raise Invalid, "policy.yml: proposals must be a list" unless list.is_a?(Array)

        seen = []
        list.map do |proposal|
          raise Invalid, "policy.yml: each proposal must be a mapping with an id" unless proposal.is_a?(Hash) && proposal.key?("id")
          raise Invalid, "policy.yml: a proposal id must be text" unless text?(proposal["id"])

          id = proposal["id"]
          raise Invalid, "policy.yml: proposal ids must be unique: #{id}" if seen.include?(id)

          seen << id
          proposal(proposal)
        end
      end

      def self.text?(value)
        value.is_a?(String) && !value.empty?
      end

      def self.proposal(proposal)
        id = proposal["id"]
        name = proposal["name"] || id
        raise Invalid, "policy.yml: proposal #{id}: name must be text" unless name.is_a?(String)

        omit = proposal["omit"] || []
        raise Invalid, "policy.yml: proposal #{id}: omit must be a list of names" unless omit.is_a?(Array) && omit.all?(String)

        proposal.merge("name" => name, "components" => components(id, proposal["components"] || [], []), "omit" => omit)
      end

      def self.components(proposal_id, list, seen)
        raise Invalid, "policy.yml: proposal #{proposal_id}: components must be a list" unless list.is_a?(Array)

        list.map do |component|
          raise Invalid, "policy.yml: proposal #{proposal_id}: each component must be a mapping with an id" unless component.is_a?(Hash) && component.key?("id")
          raise Invalid, "policy.yml: proposal #{proposal_id}: a component id must be text" unless text?(component["id"])

          id = component["id"]
          raise Invalid, "policy.yml: proposal #{proposal_id}: component ids must be unique: #{id}" if seen.include?(id)

          seen << id
          component(proposal_id, component, seen)
        end
      end

      def self.component(proposal_id, component, seen)
        prefix = "policy.yml: proposal #{proposal_id}: component #{component['id']}"
        label = component["label"] || component["id"]
        raise Invalid, "#{prefix}: label must be text" unless label.is_a?(String)

        members = component["members"] || []
        raise Invalid, "#{prefix}: members must be a list" unless members.is_a?(Array)

        members = members.map do |member|
          next member if member.is_a?(String)
          next components(proposal_id, [member], seen).first if member.is_a?(Hash)

          raise Invalid, "#{prefix}: a member is a name or a component, not #{member.inspect}"
        end
        component.merge("label" => label, "members" => members)
      end
    end
  end
end
