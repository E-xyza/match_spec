defmodule MatchSpecTest.StringMatchErrorTest do
  use ExUnit.Case, async: true

  alias MatchSpec.Fun2ms.Head
  alias MatchSpec.Fun2ms.StringMatch

  @dummy_head %Head{caller: __ENV__, bindings: %{}}

  for type <- ~w(integer float bits bitstring utf16 utf32)a do
    test "string match with #{type} fails" do
      type = {unquote(type), [], nil}

      {_, _, parts} =
        quote do
          <<a::unquote(type)>>
        end

      assert_raise CompileError,
                   ~r"invalid segment type, must be `binary`, `bytes`, or `utf8`: got `#{unquote(type)}`$",
                   fn ->
                     StringMatch.from_parts(parts, @dummy_head)
                   end
    end
  end

  describe "a string match with a match variable" do
    test "match variable with no qualifier fails" do
      {_, _, parts} =
        quote do
          <<a>>
        end

      assert_raise CompileError,
                   ~r/invalid segment, the match variable \(`a`\) must be typed `binary`, `bytes`, or `utf8`$/,
                   fn ->
                     StringMatch.from_parts(parts, @dummy_head)
                   end
    end

    test "free binaries must come at the end" do
      {_, _, parts} =
        quote do
          <<a::binary, "foo">>
        end

      assert_raise CompileError,
                   ~r/a binary match without size \(found `a`\) is only allowed at the end of a binary pattern$/,
                   fn ->
                     StringMatch.from_parts(parts, @dummy_head)
                   end
    end
  end

  test "a string match with literal string can't contain a size specifier" do
    {_, _, parts} =
      quote do
        <<"foo"::binary-size(4)>>
      end

    assert_raise CompileError,
                 ~r"invalid segment type or option for string literal, must be `binary`, `bytes`, or `utf`: got `size\(4\)`$",
                 fn ->
                   StringMatch.from_parts(parts, @dummy_head)
                 end
  end

  @pin_head %{
    @dummy_head
    | bindings: %{
        foo:
          quote do
            foo
          end
      }
  }

  describe "a string match for a pinned variable" do
    test "must be part of a bound variable" do
      {_, _, parts} =
        quote do
          <<^foo::binary-size(4)>>
        end

      assert_raise CompileError,
                   ~r"pin requires a bound variable \(got `foo`, found: \[\]\)$",
                   fn ->
                     StringMatch.from_parts(parts, @dummy_head)
                   end
    end

    test "must have a type and size specifier" do
      {_, _, parts} =
        quote do
          <<^foo>>
        end

      assert_raise CompileError,
                   ~r"invalid segment type, a pinned variable must have a type and size specifier.  Try `\^foo :: binary - size\(byte_size\(foo\)\)` in place of `\^foo`$",
                   fn ->
                     StringMatch.from_parts(parts, @pin_head)
                   end
    end

    test "must have a size specifier" do
      {_, _, parts} =
        quote do
          <<^foo::binary>>
        end

      assert_raise CompileError,
                   ~r"invalid segment type, a pinned variable must have a size specifier.  Try `\^foo :: binary - size\(byte_size\(foo\)\)` in place of `\^foo :: binary`$",
                   fn ->
                     StringMatch.from_parts(parts, @pin_head)
                   end
    end

    test "must have a size specifier in compound specifier" do
      {_, _, parts} =
        quote do
          <<^foo::binary-binary>>
        end

      assert_raise CompileError,
                   ~r"invalid segment type, a pinned variable must have a size specifier.  Try `\^foo :: binary - size\(byte_size\(foo\)\)` in place of `\^foo :: binary - binary`$",
                   fn ->
                     StringMatch.from_parts(parts, @pin_head)
                   end
    end

    test "must have a type specifier in compound specifier" do
      {_, _, parts} =
        quote do
          <<^foo::size(4)-size(4)>>
        end

      assert_raise CompileError,
                   ~r"invalid segment type, must have the type `binary`, `bytes`, or `utf8`: got `\^foo :: size\(4\) - size\(4\)`$",
                   fn ->
                     StringMatch.from_parts(parts, @pin_head)
                   end
    end
  end
end
