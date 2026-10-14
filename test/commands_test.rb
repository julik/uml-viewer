require "test_helper"
require "set"

module Uml
  module Viewer
    class CommandsTest < TestCase
      IDS = Set["Order", "folder:models", "Reports"].freeze

      def validate(body, proposal_ids: Set[])
        Commands.validate(body, ids: IDS, proposal_ids: proposal_ids)
      end

      def test_explain_on_a_class_is_accepted
        assert_equal ["explain", { "id" => "Order", "kind" => "class", "proposal_id" => nil }, nil],
                     validate({ "op" => "explain", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => nil } })
      end

      def test_omit_on_a_kind_box_is_accepted
        op, target, reason = validate({ "op" => "omit", "target" => { "id" => "folder:models", "kind" => "box", "proposal_id" => nil } })
        assert_equal ["omit", "folder:models", nil], [op, target["id"], reason]
      end

      def test_propose_has_no_target
        assert_equal ["propose", nil, nil], validate({ "op" => "propose" })
        assert_equal "propose takes no target", validate({ "op" => "propose", "target" => {} }).last
      end

      def test_context_takes_only_a_proposal_id
        assert_equal ["context", { "proposal_id" => nil }, nil], validate({ "op" => "context", "target" => { "proposal_id" => nil } })
      end

      def test_an_unknown_op_is_refused
        assert_equal "unknown op: delete", validate({ "op" => "delete" }).last
      end

      def test_an_unknown_key_is_refused
        assert_equal "unknown key: note", validate({ "op" => "propose", "note" => "x" }).last
        assert_equal "unknown key in target: extra",
                     validate({ "op" => "explain", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => nil, "extra" => 1 } }).last
      end

      def test_a_target_id_not_in_the_graph_is_refused
        assert_equal "unknown target: Ghost",
                     validate({ "op" => "omit", "target" => { "id" => "Ghost", "kind" => "class", "proposal_id" => nil } }).last
      end

      def test_an_unknown_proposal_id_is_refused_and_a_known_one_accepted
        body = { "op" => "omit", "target" => { "id" => "Order", "kind" => "class", "proposal_id" => "p1" } }
        assert_equal "unknown proposal: p1", validate(body).last
        assert_nil validate(body, proposal_ids: Set["p1"]).last
      end

      def test_a_wrong_kind_is_refused
        assert_equal "target kind must be class or box",
                     validate({ "op" => "explain", "target" => { "id" => "Order", "kind" => "file", "proposal_id" => nil } }).last
      end

      def test_a_body_that_is_not_an_object_is_refused
        assert_equal "body must be a JSON object", validate([1]).last
      end
    end
  end
end
