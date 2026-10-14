module Uml
  module Viewer
    class Resolver
      def initialize(classes:, namespaces:)
        @classes = classes
        @namespaces = namespaces
      end

      def resolve(reference, nesting:, enclosing:)
        written = reference.delete_prefix("::")
        candidates = reference.start_with?("::") ? [written] : candidates_for(written, nesting, enclosing)
        exact(candidates) || stripped(candidates, written.split("::").size)
      end

      private

      def candidates_for(written, nesting, enclosing)
        lexical = nesting.reverse.map { |scope| "#{scope}::#{written}" }
        rails = prefixes(enclosing).map { |scope| "#{scope}::#{written}" }
        (lexical + rails + [written]).uniq
      end

      def prefixes(name)
        return [] if name.nil?

        segments = name.split("::")
        segments.size.downto(1).map { |count| segments.first(count).join("::") }
      end

      def exact(candidates)
        candidates.each do |candidate|
          return [:class, candidate] if @classes.include?(candidate)
          return [:namespace, candidate] if @namespaces.include?(candidate)
        end
        nil
      end

      def stripped(candidates, written_size)
        return nil if written_size < 2

        candidates.each do |candidate|
          segments = candidate.split("::")
          1.upto(written_size - 1) do |strip|
            rest = segments[0...-strip].join("::")
            return [:class, rest] if @classes.include?(rest)
          end
        end
        nil
      end
    end
  end
end
