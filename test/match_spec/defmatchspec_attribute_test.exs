defmodule MatchSpecTest.DefmatchspecAttributeTest do
  use ExUnit.Case, async: true
  use MatchSpec

  @value 1

  describe "defmatchspec" do
    defmatchspec test_attribute_in_match() do
      {key, @value} -> key
    end

    test "attribute in match" do
      assert [{{:"$1", 1}, [], [:"$1"]}] == test_attribute_in_match()
    end

    defmatchspec test_attribute_in_guard() do
      {key, value} when value == @value -> key
    end

    test "attribute in guard" do
      assert [{{:"$1", :"$2"}, [{:==, :"$2", 1}], [:"$1"]}] == test_attribute_in_guard()
    end

    defmatchspec test_attribute_in_expression() do
      _ -> @value
    end

    test "attribute in expression" do
      assert [{:_, [], [1]}] == test_attribute_in_expression()
    end
  end
end