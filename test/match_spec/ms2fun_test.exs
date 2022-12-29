defmodule MatchSpecTest.Ms2funTest do
  use ExUnit.Case, async: true

  alias MatchSpec.Fun2ms

  defmacrop assert_identity(ast = {:fn, _, arrows}) do
    arrows = Macro.escape(arrows)

    caller =
      __CALLER__
      |> Macro.Env.prune_compile_info()
      |> Macro.escape()

    quote bind_quoted: [ast: Macro.escape(ast), arrows: arrows, caller: caller] do
      result =
        arrows
        |> Fun2ms.from_arrows(caller: caller)
        |> Code.eval_quoted([], caller)
        |> elem(0)
        |> MatchSpec.ms2fun(:code)

      assert Macro.to_string(ast) == result
    end
  end

  describe "basic functions" do
    test "identity function" do
      assert_identity(fn tuple -> tuple end)
    end

    test "ignored parameter" do
      assert_identity(fn _ -> true end)
    end
  end

  defmodule MyStruct do
    defstruct [:key, :value]
  end

  describe "matching" do
    test "v1 twople works" do
      assert_identity(fn {v1, v2} -> v1 end)
    end

    test "v1 threeple works" do
      assert_identity(fn {v1, v2, _} -> v1 end)
    end

    test "nested tuples works" do
      assert_identity(fn {{v1, v2}, _} -> v1 end)
    end

    test "nested list works" do
      assert_identity(fn {[v1], v2} -> v1 end)
    end

    test "nested map works" do
      assert_identity(fn {%{foo: v1}, v2} -> v1 end)
    end

    test "nested struct works" do
      assert_identity(fn {%MatchSpecTest.Ms2funTest.MyStruct{key: v1, value: v2}, _} -> v1 end)
    end

    test "literal string works" do
      assert_identity(fn {"v1", v1} -> v1 end)
    end

    test "literal number works" do
      assert_identity(fn {123, v1} -> v1 end)
    end

    test "can bind the whole tuple" do
      assert_identity(fn tuple = {v1, v2} -> tuple end)
    end
  end

  describe "filters" do
    # binary functions
    test "is_atom works" do
      assert_identity(fn {v1} when is_atom(v1) -> v1 end)
    end

    test "is_float works" do
      assert_identity(fn {v1} when is_float(v1) -> v1 end)
    end

    test "is_integer works" do
      assert_identity(fn {v1} when is_integer(v1) -> v1 end)
    end

    test "is_list works" do
      assert_identity(fn {v1} when is_list(v1) -> v1 end)
    end

    test "is_number works" do
      assert_identity(fn {v1} when is_number(v1) -> v1 end)
    end

    test "is_pid works" do
      assert_identity(fn {v1} when is_pid(v1) -> v1 end)
    end

    test "is_port works" do
      assert_identity(fn {v1} when is_port(v1) -> v1 end)
    end

    test "is_reference works" do
      assert_identity(fn {v1} when is_reference(v1) -> v1 end)
    end

    test "is_tuple works" do
      assert_identity(fn {v1} when is_tuple(v1) -> v1 end)
    end

    test "is_map works" do
      assert_identity(fn {v1} when is_map(v1) -> v1 end)
    end

    test "is_binary works" do
      assert_identity(fn {v1} when is_binary(v1) -> v1 end)
    end

    test "is_function works" do
      assert_identity(fn {v1} when is_function(v1) -> v1 end)
    end

    test "not works" do
      assert_identity(fn {v1} when not v1 -> v1 end)
    end

    test "and works, mapped to andalso" do
      assert_identity(fn {v1, v2} when v1 and v2 -> v1 end)
    end

    test "or works, mapped to orelse" do
      assert_identity(fn {v1, v2} when v1 or v2 -> v1 end)
    end

    test "is_map_key works, but is flipped" do
      assert_identity(fn {v1, v2} when is_map_key(v1, v2) -> v1 end)
    end

    # guard functions
    test "abs works" do
      assert_identity(fn {v1, v2} when abs(v2) -> v1 end)
    end

    test "element works, but translates to element and adds one" do
      assert_identity(fn {v1, v2} when elem(v2, 0) -> v1 end)

      # the next one gets weird (+ 1 - 1)
      # assert_identity(fn {v1, v2} when elem(v2, v1) -> v1 end)
    end

    test "hd works" do
      assert_identity(fn {v1, v2} when hd(v2) -> v1 end)
    end

    test "length works" do
      assert_identity(fn {v1, v2} when length(v2) -> v1 end)
    end

    test ":erlang.map_get works" do
      assert_identity(fn {v1, v2} when :erlang.map_get(v1, v2) -> v1 end)
    end

    test "map_size works" do
      assert_identity(fn {v1, v2} when map_size(v2) -> v1 end)
    end

    test "node works" do
      assert_identity(fn {v1, v2} when node() -> v1 end)
    end

    test "round works" do
      assert_identity(fn {v1, v2} when round(v2) -> v1 end)
    end

    test "bit_size works" do
      assert_identity(fn {v1, v2} when bit_size(v2) -> v1 end)
    end

    test "byte_size works" do
      assert_identity(fn {v1, v2} when byte_size(v2) -> v1 end)
    end

    test "tl works" do
      assert_identity(fn {v1, v2} when tl(v2) -> v1 end)
    end

    test "trunc works" do
      assert_identity(fn {v1, v2} when trunc(v2) -> v1 end)
    end

    test "binary_part works" do
      assert_identity(fn {v1, v2} when binary_part(v2, 0, 2) -> v1 end)
    end

    test "self works" do
      assert_identity(fn {v1, v2} when self() -> v1 end)
    end

    test "arithmetic operators work" do
      assert_identity(fn {v1, v2} when v1 + v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 - v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 * v2 -> v1 end)

      assert_identity(fn {v1, v2} when div(v1, v2) -> v1 end)

      assert_identity(fn {v1, v2} when rem(v1, v2) -> v1 end)
    end

    test "comparison operators work" do
      assert_identity(fn {v1, v2} when v1 > v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 >= v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 < v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 <= v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 == v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 === v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 != v2 -> v1 end)

      assert_identity(fn {v1, v2} when v1 !== v2 -> v1 end)
    end

    test "raw value" do
      assert_identity(fn {v1} when v1 -> v1 end)
    end
  end
end
