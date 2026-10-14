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

      def test_an_empty_file_gives_the_defaults
        assert_equal PolicyFile::DEFAULTS, PolicyFile.load(write(""))
      end

      def test_mutating_a_loaded_policy_leaves_the_defaults_alone
        PolicyFile.load("/no/such/policy.yml")["sources"] << "extra"
        PolicyFile.load(write("omit: [A]\n"))["skip"] << "extra"
        assert_equal %w[app lib], PolicyFile::DEFAULTS["sources"]
        assert_empty PolicyFile::DEFAULTS["skip"]
      end
    end
  end
end
