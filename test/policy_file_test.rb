require "test_helper"

module Uml
  module Viewer
    class PolicyFileTest < TestCase
      def write(text)
        path = File.join(Dir.mktmpdir, "policy.yml")
        File.write(path, text)
        path
      end

      def test_a_missing_file_gives_the_defaults
        assert_equal PolicyFile::DEFAULTS, PolicyFile.load("/no/such/policy.yml")
      end

      def test_given_keys_replace_the_defaults_and_the_rest_stay
        policy = PolicyFile.load(write("levels:\n  - [models]\n  - [services]\nomit: [ApplicationRecord]\n"))
        assert_equal [["models"], ["services"]], policy["levels"]
        assert_equal ["ApplicationRecord"], policy["omit"]
        assert_equal %w[app lib], policy["sources"]
      end

      def test_broken_yaml_raises_with_the_line_number
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("levels:\n  - [models\nomit: []\n")) }
        assert_match(/\Apolicy\.yml line \d+: /, error.message)
      end

      def test_a_wrong_type_raises_with_the_key
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("levels: models\n")) }
        assert_equal "policy.yml: levels must be a list of lists of folder names", error.message
      end

      def test_an_omit_that_is_not_a_list_of_strings_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("omit: 3\n")) }
        assert_equal "policy.yml: omit must be a list of names", error.message
      end

      def test_a_date_value_raises_invalid_with_the_problem
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("title: 2026-10-14\n")) }
        assert_equal "policy.yml: Tried to load unspecified class: Date", error.message
      end

      def test_a_symbol_value_raises_invalid_with_the_problem
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("omit: :sym\n")) }
        assert_equal "policy.yml: Tried to load unspecified class: Symbol", error.message
      end

      def test_an_alias_raises_invalid_with_the_problem
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("a: &x [1]\nb: *x\n")) }
        assert_match(/\Apolicy\.yml: Alias parsing was not enabled/, error.message)
      end

      def test_a_file_that_is_not_a_mapping_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("- a\n- b\n")) }
        assert_equal "policy.yml: the file must hold a mapping", error.message
      end

      def test_edge_kinds_that_is_not_a_mapping_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("edge_kinds: [a]\n")) }
        assert_equal "policy.yml: edge_kinds must be a mapping", error.message
      end

      def test_proposals_that_is_not_a_list_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("proposals: {a: 1}\n")) }
        assert_equal "policy.yml: proposals must be a list", error.message
      end

      def test_a_proposal_that_is_not_a_mapping_with_an_id_raises
        ["proposals: [1]\n", "proposals:\n  - name: no id\n"].each do |text|
          error = assert_raises(PolicyFile::Invalid, text) { PolicyFile.load(write(text)) }
          assert_equal "policy.yml: each proposal must be a mapping with an id", error.message
        end
      end

      def test_a_proposal_with_an_id_loads_with_its_defaults_filled_in
        policy = PolicyFile.load(write("proposals:\n  - id: p1\n    name: first\n  - id: p2\n"))
        assert_equal [{ "id" => "p1", "name" => "first", "components" => [], "omit" => [] },
                      { "id" => "p2", "name" => "p2", "components" => [], "omit" => [] }], policy["proposals"]
      end

      def test_components_get_a_label_and_nested_components_load
        text = "proposals:\n  - id: p1\n    components:\n      - id: core\n        members:\n          - Order\n          - id: billing\n            label: Billing\n            members: [Billing]\n"
        component = PolicyFile.load(write(text))["proposals"].first["components"].first
        assert_equal "core", component["label"]
        assert_equal "Order", component["members"][0]
        assert_equal({ "id" => "billing", "label" => "Billing", "members" => ["Billing"] }, component["members"][1])
      end

      def test_a_component_without_members_gets_an_empty_list
        component = PolicyFile.load(write("proposals:\n  - id: p1\n    components:\n      - id: core\n"))["proposals"].first["components"].first
        assert_equal [], component["members"]
      end

      def test_each_wrong_proposal_shape_names_the_proposal_and_the_problem
        {
          "proposals:\n  - id: ''\n" => "policy.yml: a proposal id must be text",
          "proposals:\n  - id: 3\n" => "policy.yml: a proposal id must be text",
          "proposals:\n  - id: p1\n    components:\n      - id: 4\n" => "policy.yml: proposal p1: a component id must be text",
          "proposals:\n  - id: p1\n  - id: p1\n" => "policy.yml: proposal ids must be unique: p1",
          "proposals:\n  - id: p1\n    name: [a]\n" => "policy.yml: proposal p1: name must be text",
          "proposals:\n  - id: p1\n    omit: Order\n" => "policy.yml: proposal p1: omit must be a list of names",
          "proposals:\n  - id: p1\n    components: core\n" => "policy.yml: proposal p1: components must be a list",
          "proposals:\n  - id: p1\n    components: [core]\n" => "policy.yml: proposal p1: each component must be a mapping with an id",
          "proposals:\n  - id: p1\n    components:\n      - id: a\n      - id: a\n" => "policy.yml: proposal p1: component ids must be unique: a",
          "proposals:\n  - id: p1\n    components:\n      - id: a\n        members:\n          - id: a\n" => "policy.yml: proposal p1: component ids must be unique: a",
          "proposals:\n  - id: p1\n    components:\n      - id: a\n        label: 3\n" => "policy.yml: proposal p1: component a: label must be text",
          "proposals:\n  - id: p1\n    components:\n      - id: a\n        members: Order\n" => "policy.yml: proposal p1: component a: members must be a list",
          "proposals:\n  - id: p1\n    components:\n      - id: a\n        members: [3]\n" => "policy.yml: proposal p1: component a: a member is a name or a component, not 3"
        }.each do |text, message|
          error = assert_raises(PolicyFile::Invalid, text) { PolicyFile.load(write(text)) }
          assert_equal message, error.message
        end
      end

      def test_a_list_key_without_a_value_gives_the_empty_default
        policy = PolicyFile.load(write("omit:\n  # - Order\nforeign:\nproposals:\nedge_kinds:\n"))
        assert_empty policy["omit"]
        assert_empty policy["foreign"]
        assert_empty policy["proposals"]
        assert_empty policy["edge_kinds"]
      end

      def test_an_empty_file_gives_the_defaults
        assert_equal PolicyFile::DEFAULTS, PolicyFile.load(write(""))
      end

      def test_mutating_a_loaded_policy_leaves_the_defaults_alone
        PolicyFile.load("/no/such/policy.yml")["sources"] << "extra"
        PolicyFile.load(write("omit: [A]\n"))["skip"] << "extra"
        assert_equal %w[app lib], PolicyFile::DEFAULTS["sources"]
        assert_empty PolicyFile::DEFAULTS["skip"]
      end

      def test_an_edge_kinds_value_that_is_no_kind_raises_with_the_rule
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("edge_kinds:\n  \"Order -> User\": friend\n")) }
        assert_equal 'policy.yml: edge_kinds maps "From -> To" to one of inheritance, implements, association, dependency', error.message
      end

      def test_an_edge_kinds_key_without_an_arrow_raises_with_the_rule
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("edge_kinds:\n  Order: association\n")) }
        assert_match(/\Apolicy\.yml: edge_kinds maps/, error.message)
      end

      def test_a_valid_edge_kinds_entry_loads
        assert_equal({ "Order -> User" => "association" }, PolicyFile.load(write("edge_kinds:\n  \"Order -> User\": association\n"))["edge_kinds"])
      end

      def test_a_title_that_is_not_text_raises
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("title: 12\n")) }
        assert_equal "policy.yml: title must be text", error.message
      end

      def test_a_syntax_error_names_the_line_psych_reports
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("title: x\nsources: [app]\nlevels: [\n")) }
        assert_equal "policy.yml line 4: did not find expected node content", error.message
      end

      def test_crap_cutoffs_must_be_nine_rising_numbers
        message = "policy.yml: crap_cutoffs must be 9 numbers in rising order"
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("crap_cutoffs: [5, 10]\n")) }
        assert_equal message, error.message
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("crap_cutoffs: [5, 10, 15, 20, 30, 40, 60, 80, 70]\n")) }
        assert_equal message, error.message
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("crap_cutoffs: [a, 10, 15, 20, 30, 40, 60, 80, 120]\n")) }
        assert_equal message, error.message
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("crap_cutoffs: [5, 5, 15, 20, 30, 40, 60, 80, 120]\n")) }
        assert_equal message, error.message
        error = assert_raises(PolicyFile::Invalid) { PolicyFile.load(write("crap_cutoffs: [5, 10, 15, 20, 30, 40, 60, 80, 120, 200]\n")) }
        assert_equal message, error.message
        assert_equal [1, 2, 3, 4, 5, 6, 7, 8, 9], PolicyFile.load(write("crap_cutoffs: [1, 2, 3, 4, 5, 6, 7, 8, 9]\n"))["crap_cutoffs"]
      end
    end
  end
end
