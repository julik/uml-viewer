module Uml
  module Viewer
    module Inflector
      SINGULAR = [
        [/people\z/, "person"], [/children\z/, "child"], [/ies\z/, "y"], [/sses\z/, "ss"], [/xes\z/, "x"],
        [/ches\z/, "ch"], [/shes\z/, "sh"], [/ses\z/, "s"], [/s\z/, ""]
      ].freeze

      def self.singularize(word)
        pattern, replacement = SINGULAR.find { |rule, _| word.match?(rule) }
        pattern ? word.sub(pattern, replacement) : word
      end

      def self.camelize(word)
        word.split("_").map(&:capitalize).join
      end
    end
  end
end
