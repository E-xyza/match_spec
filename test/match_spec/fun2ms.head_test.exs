defmodule MatchSpecTest.Fun2ms.HeadTest do
  use ExUnit.Case, async: true

  alias MatchSpec.Fun2ms.Head

  describe "for an empty head do" do
    test "the head_ast is :_" do
      assert %{head_ast: :_, pins: %{}} =
               Head.from_arg_ast(
                 quote do
                   _
                 end,
                 __ENV__
               )
    end

    test "the head_ast is :_ even if it's named" do
      assert %{head_ast: :_, pins: %{}} =
               Head.from_arg_ast(
                 quote do
                   _named
                 end,
                 __ENV__
               )
    end
  end

  describe "for a variable head" do
    test "the head_ast is :_, but we get a named top" do
      assert %{head_ast: :_, pins: %{}, bindings: %{v: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   v
                 end,
                 __ENV__
               )
    end

    test "multiple variables get assigned if we have match operator" do
      assert %{head_ast: :_, pins: %{}, bindings: %{v1: :"$_", v2: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   v1 = v2
                 end,
                 __ENV__
               )
    end
  end

  describe "for a patterned head" do
    test "basic twople head_ast" do
      assert %{head_ast: {:_, :_}, pins: %{}} =
               Head.from_arg_ast(
                 quote do
                   {_, _}
                 end,
                 __ENV__
               )
    end

    test "twople with a variable" do
      assert %{head_ast: {:"$1", :_}, pins: %{}, bindings: %{v: 1}} =
               Head.from_arg_ast(
                 quote do
                   {v, _}
                 end,
                 __ENV__
               )
    end

    test "twople with two variables" do
      assert %{head_ast: {:"$1", :"$2"}, pins: %{}, bindings: %{v1: 1, v2: 2}} =
               Head.from_arg_ast(
                 quote do
                   {v1, v2}
                 end,
                 __ENV__
               )
    end

    test "twople with the same variable" do
      assert %{head_ast: {:"$1", :"$1"}, pins: %{}, bindings: %{v: 1}} =
               Head.from_arg_ast(
                 quote do
                   {v, v}
                 end,
                 __ENV__
               )
    end

    @single (quote do
               {:_}
             end)

    test "other tuple head_ast" do
      assert %{head_ast: @single, pins: %{}} =
               Head.from_arg_ast(
                 quote do
                   {_}
                 end,
                 __ENV__
               )
    end

    test "can have both a top level and a head_ast" do
      assert %{head_ast: @single, pins: %{}, bindings: %{v: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   v = {_}
                 end,
                 __ENV__
               )
    end

    test "can have multiple top levels and a head_ast: order 1" do
      assert %{head_ast: @single, pins: %{}, bindings: %{v1: :"$_", v2: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   v1 = {_} = v2
                 end,
                 __ENV__
               )
    end

    test "can have multiple top levels and a head_ast: order 2" do
      assert %{head_ast: @single, pins: %{}, bindings: %{v1: :"$_", v2: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   v1 = v2 = {_}
                 end,
                 __ENV__
               )
    end

    test "can have multiple top levels and a head_ast: order 3" do
      assert %{head_ast: @single, pins: %{}, bindings: %{v1: :"$_", v2: :"$_"}} =
               Head.from_arg_ast(
                 quote do
                   {_} = v1 = v2
                 end,
                 __ENV__
               )
    end

    test "can't have multiple patterns, even if they are the same" do
      regex =
        ~r"only one structured pattern match allowed in the head, multiple patterns found: `{_}` and `{_}`$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            {_} = {_}
          end,
          __ENV__
        )
      end
    end
  end

  @pinned %{
    pinned:
      quote do
        pinned
      end
  }

  describe "can pin" do
    test "at the top level" do
      assert %{head_ast: :_, pins: %{"$_": {:pinned, _, _}}} =
               Head.from_arg_ast(
                 quote do
                   ^pinned
                 end,
                 @pinned,
                 __ENV__
               )
    end

    test "with a structured pin" do
      assert %{
               head_ast: {:"$1", :_},
               pins: %{"$1": {:pinned, _, _}}
             } =
               Head.from_arg_ast(
                 quote do
                   {^pinned, _}
                 end,
                 @pinned,
                 __ENV__
               )
    end

    test "can double pin" do
      assert %{
               head_ast: {:"$1", :"$1"},
               pins: %{"$1": {:pinned, _, _}}
             } =
               Head.from_arg_ast(
                 quote do
                   {^pinned, ^pinned}
                 end,
                 @pinned,
                 __ENV__
               )
    end

    test "missing pin in top match causes error" do
      regex = ~r"pin requires a bound variable \(got `missing`, found: \[\]\)$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            ^missing
          end,
          __ENV__
        )
      end
    end

    test "can't have two pins at the top level" do
      regex = ~r"only one pin is allowed in the head, multiple pins found: `\^v1` and `\^v2`$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            ^v1 = ^v2
          end,
          %{v1: {:v1, [], nil}, v2: {:v2, [], nil}},
          __ENV__
        )
      end
    end

    test "can't have a pin and a structured pattern match, 1" do
      regex =
        ~r"cannot use a pin in the same head as a structured pattern match, found: `\^v` and `{_}`$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            ^v = {_}
          end,
          %{v: {:v, [], nil}},
          __ENV__
        )
      end
    end

    test "can't have a pin and a structured pattern match, 2" do
      regex =
        ~r"cannot use a pin in the same head as a structured pattern match, found: `{_}` and `\^v`$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            {_} = ^v
          end,
          %{v: {:v, [], nil}},
          __ENV__
        )
      end
    end

    test "string concat not allowed in header" do
      regex = ~r"top match must be a tuple \(got: \"foo\" <> bar\)$"

      assert_raise CompileError, regex, fn ->
        Head.from_arg_ast(
          quote do
            "foo" <> bar
          end,
          __ENV__
        )
      end
    end
  end
end
