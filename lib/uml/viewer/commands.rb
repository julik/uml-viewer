module Uml
  module Viewer
    module Commands
      TARGET_KEYS = {
        "explain" => %w[id kind proposal_id],
        "omit" => %w[id kind proposal_id],
        "context" => %w[proposal_id],
        "propose" => nil
      }.freeze

      def self.validate(body, ids:, proposal_ids:)
        return refuse("body must be a JSON object") unless body.is_a?(Hash)

        extra = (body.keys - %w[op target]).first
        return refuse("unknown key: #{extra}") if extra

        op = body["op"]
        return refuse("unknown op: #{op}") unless TARGET_KEYS.key?(op)

        keys = TARGET_KEYS[op]
        return refuse("#{op} takes no target") if keys.nil? && body.key?("target")
        return [op, nil, nil] if keys.nil?

        target = body["target"]
        return refuse("#{op} needs a target") unless target.is_a?(Hash)

        extra = (target.keys - keys).first
        return refuse("unknown key in target: #{extra}") if extra
        return refuse("target needs #{(keys - target.keys).join(', ')}") unless (keys - target.keys).empty?

        reason = check_target(target, ids, proposal_ids)
        reason ? refuse(reason) : [op, target, nil]
      end

      def self.check_target(target, ids, proposal_ids)
        proposal = target["proposal_id"]
        return "unknown proposal: #{proposal}" unless proposal.nil? || proposal_ids.include?(proposal)
        return nil unless target.key?("id")
        return "target kind must be class or box" unless %w[class box].include?(target["kind"])
        return "unknown target: #{target['id']}" unless ids.include?(target["id"])

        nil
      end

      def self.refuse(reason)
        [nil, nil, reason]
      end
    end
  end
end
