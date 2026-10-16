require "test_helper"

module Uml
  module Viewer
    class OperationsTest < TestCase
      def ops(source, file: "app/models/order.rb")
        Operations.new(Prism.parse(source).value, file).collect
      end

      def shape(source)
        ops(source).map { |op| [op["name"], op["visibility"]] }
      end

      def test_an_op_has_its_name_visibility_cc_file_and_lines
        assert_equal [{ "name" => "total", "visibility" => "public", "cc" => 2, "file" => "app/models/order.rb", "line_start" => 2, "line_end" => 4 }],
                     ops("class Order\n  def total\n    0 if empty?\n  end\nend\n")
      end

      def test_an_endless_def_starts_and_ends_on_one_line
        assert_equal [[3, 3]], ops("class Order\n\n  def total = 0\nend\n").map { |op| op.values_at("line_start", "line_end") }
      end

      def test_private_without_arguments_applies_to_the_defs_below_it
        assert_equal [["a", "public"], ["b", "private"], ["c", "protected"]],
                     shape("class X\n  def a; end\n  private\n  def b; end\n  protected\n  def c; end\nend\n")
      end

      def test_private_with_a_name_or_a_def_applies_to_that_method_only
        assert_equal [["a", "private"], ["b", "private"], ["c", "public"]],
                     shape("class X\n  def a; end\n  private :a\n  private def b; end\n  def c; end\nend\n")
      end

      def test_public_with_a_name_after_private_makes_that_method_public
        assert_equal [["a", "public"]], shape("class X\n  private\n  def a; end\n  public :a\nend\n")
      end

      def test_def_self_is_public_under_private_unless_private_class_method
        assert_equal [["self.a", "public"], ["self.b", "private"], ["self.c", "private"]],
                     shape("class X\n  private\n  def self.a; end\n  def self.b; end\n  private_class_method :b\n  private_class_method def self.c; end\nend\n")
      end

      def test_a_def_inside_class_self_is_a_singleton_op_with_its_own_visibility
        assert_equal [["self.a", "public"], ["self.b", "private"]],
                     shape("class X\n  class << self\n    def a; end\n    private\n    def b; end\n  end\nend\n")
      end

      def test_a_def_in_a_class_methods_block_is_a_singleton_op
        assert_equal [["self.find_all", "public"]],
                     shape("module Trackable\n  extend ActiveSupport::Concern\n  class_methods do\n    def find_all; end\n  end\nend\n")
      end

      def test_a_def_inside_a_def_is_not_an_op
        assert_equal [["outer", "public"]], shape("class X\n  def outer\n    def inner; end\n  end\nend\n")
      end

      def test_a_def_in_a_data_define_block_and_a_def_in_a_nested_class_are_ops_of_the_file
        assert_equal [["area", "public"], ["code", "public"]],
                     shape("module Shapes\n  Circle = Data.define(:r) do\n    def area = r * r\n  end\n\n  class Error < StandardError\n    def code = 1\n  end\nend\n")
      end

      def test_private_in_a_nested_class_does_not_leak_into_the_outer_class
        assert_equal [["inner", "private"], ["outer", "public"]],
                     shape("class X\n  class Y\n    private\n    def inner; end\n  end\n  def outer; end\nend\n")
      end
    end
  end
end
