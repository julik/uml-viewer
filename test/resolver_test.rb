require "test_helper"
require "set"

module Uml
  module Viewer
    class ResolverTest < TestCase
      CLASSES = Set["Order", "User", "Reports::Summary", "Shop::Customer", "Shop::Store",
                    "Stats::Event", "Stats::Visit", "Top"]
      NAMESPACES = Set["Reports", "Shop", "Stats"]

      def resolver
        Resolver.new(classes: CLASSES, namespaces: NAMESPACES)
      end

      def test_a_constant_inside_a_class_resolves_to_that_class
        assert_equal [:class, "Reports::Summary"],
                     resolver.resolve("Reports::Summary::STATUS_LABELS", nesting: ["Order"], enclosing: "Order")
      end

      def test_a_top_level_class_is_found_from_inside_a_namespace
        assert_equal [:class, "Order"],
                     resolver.resolve("Order", nesting: ["Reports", "Reports::Summary"], enclosing: "Reports::Summary")
      end

      def test_exact_match_of_a_nested_class_wins_over_stripping_to_its_parent_class
        resolver = Resolver.new(classes: Set["Reports::Summary", "Reports::Summary::Row"], namespaces: Set["Reports"])
        assert_equal [:class, "Reports::Summary::Row"],
                     resolver.resolve("Summary::Row", nesting: ["Reports"], enclosing: "Reports")
      end

      def test_a_compact_class_finds_a_sibling_through_the_rails_prefix_step
        assert_equal [:class, "Shop::Store"],
                     resolver.resolve("Store", nesting: ["Shop::Customer"], enclosing: "Shop::Customer")
      end

      def test_a_nested_class_finds_a_sibling_through_lexical_nesting
        assert_equal [:class, "Stats::Visit"],
                     resolver.resolve("Visit", nesting: ["Stats", "Stats::Event"], enclosing: "Stats::Event")
      end

      def test_a_bare_unknown_constant_is_foreign_and_never_strips_to_the_enclosing_class
        assert_nil resolver.resolve("JSON", nesting: ["Reports", "Reports::Summary"], enclosing: "Reports::Summary")
      end

      def test_strip_keeps_the_first_written_segment
        assert_nil resolver.resolve("Faraday::Connection", nesting: ["Order"], enclosing: "Order")
      end

      def test_a_reference_starting_with_double_colon_tries_only_the_top_level
        resolver = Resolver.new(classes: Set["Top", "Shop::Top"], namespaces: Set["Shop"])
        assert_equal [:class, "Top"], resolver.resolve("::Top", nesting: ["Shop"], enclosing: "Shop")
        assert_equal [:class, "Shop::Top"], resolver.resolve("Top", nesting: ["Shop"], enclosing: "Shop")
      end

      def test_a_namespace_matches_exactly
        assert_equal [:namespace, "Reports"], resolver.resolve("Reports", nesting: ["Order"], enclosing: "Order")
      end

      def test_the_innermost_lexical_candidate_wins
        resolver = Resolver.new(classes: Set["A::B::Foo", "A::Foo", "Foo"], namespaces: Set["A", "A::B"])
        assert_equal [:class, "A::B::Foo"], resolver.resolve("Foo", nesting: ["A", "A::B"], enclosing: "A::B")
      end

      def test_at_the_top_level_only_the_reference_itself_is_a_candidate
        assert_equal [:class, "User"], resolver.resolve("User", nesting: [], enclosing: nil)
      end

      def test_the_strip_step_also_works_on_a_rails_prefix_candidate
        assert_equal [:class, "Shop::Store"],
                     resolver.resolve("Store::KINDS", nesting: ["Shop::Customer"], enclosing: "Shop::Customer")
      end

      def test_a_reference_of_four_segments_strips_down_to_the_class
        assert_equal [:class, "Reports::Summary"],
                     resolver.resolve("Reports::Summary::Row::WIDTH", nesting: ["Order"], enclosing: "Order")
      end

      def test_a_leading_double_colon_tries_only_the_top_level
        resolver = Resolver.new(classes: Set["Order", "Shop::Order"], namespaces: Set["Shop"])
        assert_equal [:class, "Order"], resolver.resolve("::Order", nesting: ["Shop"], enclosing: "Shop")
      end

      def test_the_strip_step_keeps_the_first_written_segment
        assert_nil resolver.resolve("Foo::BAR", nesting: ["Reports", "Reports::Summary"], enclosing: "Reports::Summary")
      end
    end
  end
end
