require "test_helper"

module Uml
  module Viewer
    class InflectorTest < TestCase
      def test_each_singularize_rule_in_its_order
        assert_equal "person", Inflector.singularize("people")
        assert_equal "sales_person", Inflector.singularize("sales_people")
        assert_equal "child", Inflector.singularize("children")
        assert_equal "category", Inflector.singularize("categories")
        assert_equal "address", Inflector.singularize("addresses")
        assert_equal "access", Inflector.singularize("accesses")
        assert_equal "box", Inflector.singularize("boxes")
        assert_equal "batch", Inflector.singularize("batches")
        assert_equal "wish", Inflector.singularize("wishes")
        assert_equal "status", Inflector.singularize("statuses")
        assert_equal "user", Inflector.singularize("users")
        assert_equal "user", Inflector.singularize("user")
      end

      def test_camelize_joins_the_snake_parts
        assert_equal "OrderAddress", Inflector.camelize("order_address")
        assert_equal "ShippingBatch", Inflector.camelize(Inflector.singularize("shipping_batches"))
        assert_equal "User", Inflector.camelize("user")
      end
    end
  end
end
