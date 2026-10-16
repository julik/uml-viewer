require "test_helper"

module Uml
  module Viewer
    class ComplexityTest < TestCase
      def cc(source)
        Complexity.of(Prism.parse(source).value.statements.body.first)
      end

      def test_the_spec_example_with_one_if_one_and_one_rescue_and_one_safe_call_has_cc_5
        assert_equal 5, cc(<<~RUBY)
          def check(order)
            return if order.nil?
            order.paid? && order.shipped?
            order&.total
          rescue ArgumentError
            0
          end
        RUBY
      end

      def test_a_method_without_branches_has_cc_1
        assert_equal 1, cc("def total = 0")
        assert_equal 1, cc("def empty; end")
      end

      def test_each_conditional_form_counts_one
        assert_equal 2, cc("def x\n  a if b\nend"), "modifier if"
        assert_equal 2, cc("def x\n  b ? 1 : 2\nend"), "ternary"
        assert_equal 2, cc("def x\n  unless b then a end\nend"), "unless"
        assert_equal 3, cc("def x\n  if a then 1 elsif b then 2 else 3 end\nend"), "if with elsif"
      end

      def test_each_loop_form_counts_one
        assert_equal 2, cc("def x\n  a while b\nend"), "while"
        assert_equal 2, cc("def x\n  a until b\nend"), "until"
        assert_equal 2, cc("def x\n  for i in list do a end\nend"), "for"
      end

      def test_each_when_and_each_in_counts_one
        assert_equal 3, cc("def x\n  case a\n  when 1 then :one\n  when 2 then :two\n  else :many\n  end\nend")
        assert_equal 3, cc("def x\n  case a\n  in Integer then 1\n  in String then 2\n  end\nend")
      end

      def test_each_rescue_clause_counts_one
        assert_equal 3, cc("def x\n  a\nrescue A\n  1\nrescue B\n  2\nend"), "two rescue clauses"
        assert_equal 2, cc("def x\n  a rescue nil\nend"), "rescue modifier"
      end

      def test_boolean_operators_and_short_circuit_writes_count_one_each
        assert_equal 3, cc("def x\n  a and b or c\nend"), "and, or"
        assert_equal 2, cc("def x\n  @a ||= 1\nend"), "instance variable ||="
        assert_equal 2, cc("def x\n  a &&= 1\nend"), "local &&="
        assert_equal 2, cc("def x\n  self.a ||= 1\nend"), "attribute ||="
      end

      def test_an_iterator_block_does_not_count_but_a_branch_inside_it_does
        assert_equal 1, cc("def x\n  list.each { |item| item }\nend")
        assert_equal 2, cc("def x\n  list.each { |item| item if item }\nend")
      end

      def test_a_nested_def_counts_for_the_method_that_holds_it
        assert_equal 2, cc("def x\n  def y\n    a if b\n  end\nend")
      end
    end
  end
end
