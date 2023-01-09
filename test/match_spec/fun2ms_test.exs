defmodule MatchSpecTest.Fun2msTest do
  use ExUnit.Case, async: true

  require MatchSpec

  describe "basic fun2ms" do
    test "works" do
      assert [{:_, [], [:"$_"]}] == MatchSpec.fun2ms(fn data -> data end)
    end

    test "can ignore the parameter" do
      assert [{:_, [], [true]}] == MatchSpec.fun2ms(fn _ -> true end)
    end
  end

  defmodule MyStruct do
    defstruct [:key, :value]
  end

  # for guards
  require Integer
  defguardp is_five(x) when x === 5

  describe "matching" do
    test "a twople works" do
      assert [{{:"$1", :"$2"}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {a, b} -> a end)
    end

    test "a threeple works" do
      assert [{{:"$1", :"$2", :_}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {a, b, _} -> a end)
    end

    test "nested tuples works" do
      assert [{{{:"$1", :"$2"}, :_}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {{a, b}, _} -> a end)
    end

    test "nested list works" do
      assert [{{[:"$1"], :"$2"}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {[a], b} -> a end)
    end

    test "nested map works" do
      assert [{{%{foo: :"$1"}, :"$2"}, [], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {%{foo: a}, b} -> a end)
    end

    test "nested struct works" do
      assert [{{%MyStruct{key: :"$1", value: :"$2"}, :_}, [], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {%MyStruct{key: a, value: b}, _} -> a end)
    end

    test "literal string works" do
      assert [{{"a", :"$1"}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {"a", a} -> a end)
    end

    test "literal number works" do
      assert [{{123, :"$1"}, [], [:"$1"]}] == MatchSpec.fun2ms(fn {123, a} -> a end)
    end

    test "can bind the whole tuple" do
      assert [{{:"$1", :"$2"}, [], [:"$_"]}] == MatchSpec.fun2ms(fn tuple = {a, b} -> tuple end)
    end
  end

  describe "filters" do
    # binary functions
    test "is_atom works" do
      assert [{{:"$1"}, [{:is_atom, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_atom(a) -> a end)
    end

    test "is_float works" do
      assert [{{:"$1"}, [{:is_float, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_float(a) -> a end)
    end

    test "is_integer works" do
      assert [{{:"$1"}, [{:is_integer, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_integer(a) -> a end)
    end

    test "is_list works" do
      assert [{{:"$1"}, [{:is_list, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_list(a) -> a end)
    end

    test "is_number works" do
      assert [{{:"$1"}, [{:is_number, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_number(a) -> a end)
    end

    test "is_pid works" do
      assert [{{:"$1"}, [{:is_pid, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_pid(a) -> a end)
    end

    test "is_port works" do
      assert [{{:"$1"}, [{:is_port, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_port(a) -> a end)
    end

    test "is_reference works" do
      assert [{{:"$1"}, [{:is_reference, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_reference(a) -> a end)
    end

    test "is_tuple works" do
      assert [{{:"$1"}, [{:is_tuple, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_tuple(a) -> a end)
    end

    test "is_map works" do
      assert [{{:"$1"}, [{:is_map, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_map(a) -> a end)
    end

    test "is_binary works" do
      assert [{{:"$1"}, [{:is_binary, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_binary(a) -> a end)
    end

    test "is_function works" do
      assert [{{:"$1"}, [{:is_function, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when is_function(a) -> a end)
    end

    test "not works" do
      assert [{{:"$1"}, [{:not, :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when not a -> a end)
    end

    test "and works, mapped to andalso" do
      assert [{{:"$1", :"$2"}, [{:andalso, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a and b -> a end)
    end

    test "or works, mapped to orelse" do
      assert [{{:"$1", :"$2"}, [{:orelse, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a or b -> a end)
    end

    test "is_map_key works, but is flipped" do
      assert [{{:"$1", :"$2"}, [{:is_map_key, :"$2", :"$1"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when is_map_key(a, b) -> a end)
    end

    # guard functions
    test "abs works" do
      assert [{{:"$1", :"$2"}, [{:abs, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when abs(b) -> a end)
    end

    test "element works, but translates to element and adds one" do
      assert [{{:"$1", :"$2"}, [{:element, 1, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when elem(b, 0) -> a end)

      assert [{{:"$1", :"$2"}, [{:element, {:+, :"$1", 1}, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when elem(b, a) -> a end)
    end

    test "hd works" do
      assert [{{:"$1", :"$2"}, [{:hd, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when hd(b) -> a end)
    end

    test "length works" do
      assert [{{:"$1", :"$2"}, [{:length, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when length(b) -> a end)
    end

    test ":erlang.map_get works" do
      assert [{{:"$1", :"$2"}, [{:map_get, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when :erlang.map_get(a, b) -> a end)
    end

    test "dot dereferencing for map_get works" do
      assert [{{:"$1", :"$2"}, [{:map_get, :foo, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when b.foo -> a end)

      assert [{{:"$1", :"$2"}, [{:map_get, :bar, {:map_get, :foo, :"$2"}}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when b.foo.bar -> a end)
    end

    test "map_size works" do
      assert [{{:"$1", :"$2"}, [{:map_size, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when map_size(b) -> a end)
    end

    test "node works" do
      assert [{{:"$1", :"$2"}, [{:node}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when node() -> a end)
    end

    test "round works" do
      assert [{{:"$1", :"$2"}, [{:round, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when round(b) -> a end)
    end

    test "size works" do
      assert [{{:"$1", :"$2"}, [{:size, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when size(b) -> a end)
    end

    test "bit_size works" do
      assert [{{:"$1", :"$2"}, [{:bit_size, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when bit_size(b) -> a end)
    end

    test "byte_size works" do
      assert [{{:"$1", :"$2"}, [{:byte_size, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when byte_size(b) -> a end)
    end

    test "tl works" do
      assert [{{:"$1", :"$2"}, [{:tl, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when tl(b) -> a end)
    end

    test "trunc works" do
      assert [{{:"$1", :"$2"}, [{:trunc, :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when trunc(b) -> a end)
    end

    test "binary_part works" do
      assert [{{:"$1", :"$2"}, [{:binary_part, :"$2", 0, 2}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when binary_part(b, 0, 2) -> a end)
    end

    test "self works" do
      assert [{{:"$1", :"$2"}, [{:self}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when self() -> a end)
    end

    test "arithmetic operators work" do
      assert [{{:"$1", :"$2"}, [{:+, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a + b -> a end)

      assert [{{:"$1", :"$2"}, [{:-, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a - b -> a end)

      assert [{{:"$1", :"$2"}, [{:*, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a * b -> a end)

      assert [{{:"$1", :"$2"}, [{:div, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when div(a, b) -> a end)

      assert [{{:"$1", :"$2"}, [{:rem, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when rem(a, b) -> a end)
    end

    test "comparison operators work" do
      assert [{{:"$1", :"$2"}, [{:>, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a > b -> a end)

      assert [{{:"$1", :"$2"}, [{:>=, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a >= b -> a end)

      assert [{{:"$1", :"$2"}, [{:<, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a < b -> a end)

      assert [{{:"$1", :"$2"}, [{:"=<", :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a <= b -> a end)

      assert [{{:"$1", :"$2"}, [{:==, :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a == b -> a end)

      assert [{{:"$1", :"$2"}, [{:"=:=", :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a === b -> a end)

      assert [{{:"$1", :"$2"}, [{:"/=", :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a != b -> a end)

      assert [{{:"$1", :"$2"}, [{:"=/=", :"$1", :"$2"}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a, b} when a !== b -> a end)
    end

    test "raw value" do
      assert [{{:"$1"}, [:"$1"], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when a -> a end)
    end

    test "builtin custom guards work" do
      assert [{{:"$1"}, [{:andalso, {:is_integer, :"$1"}, {:==, {:band, :"$1", 1}, 0}}], [:"$1"]}] ==
               MatchSpec.fun2ms(fn {a} when Integer.is_even(a) -> a end)
    end

    test "local custom guards work" do
      assert [{{:"$1"}, [{:"=:=", :"$1", 5}], [true]}] ==
               MatchSpec.fun2ms(fn {a} when is_five(a) -> true end)
    end

    test "the special guard `in` works" do
      assert [{{:"$1"}, [{:orelse, {:"=:=", :"$1", :foo}, {:"=:=", :"$1", :bar}}], [true]}] ==
               MatchSpec.fun2ms(fn {a} when a in [:foo, :bar] -> true end)
    end

    test "multiple when clauses are interpreted as orelse clauses" do
      assert [{{:"$1"}, [{:orelse, {:"=:=", :"$1", :foo}, {:"=:=", :"$1", :bar}}], [true]}] ==
               MatchSpec.fun2ms(fn {a} when a === :foo when a === :bar -> true end)
    end

    test "dot syntax for map_get works" do
      assert [{{:"$1"}, [{:map_get, :b, :"$1"}], [true]}] ==
               MatchSpec.fun2ms(fn {a} when a.b -> true end)
    end

    test "strange lists work" do
      assert [{{[:"$1" | :"$2"]}, [], [{{:"$1", :"$2"}}]}] ==
               MatchSpec.fun2ms(fn {[a | b]} -> {a, b} end)
    end

    test "local variables can be bound" do
      bar = :bar
      assert [{{:"$1"}, [{:"=:=", :"$1", :bar}], [true]}] ==
               MatchSpec.fun2ms(fn {a} when a === bar -> true end)
    end
  end

  describe "matching on binaries" do
    test "matching on extended binaries works" do
      assert [
               {{:"$1"}, [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]}
             ] = MatchSpec.fun2ms(fn {<<"foo", a::binary>>} -> a end)
    end

    test "with adjacent binaries will concatenate" do
      assert [
               {{:"$1"},
                [
                  {:"=:=", {:binary_part, :"$1", 0, 6}, {:const, "foobar"}}
                ], [{:binary_part, :"$1", 6, {:-, {:byte_size, :"$1"}, 6}}]}
             ] = MatchSpec.fun2ms(fn {<<"foo", "bar", a::binary>>} -> a end)
    end

    test "with mix with char literals" do
      assert [
               {{:"$1"}, [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]}
             ] = MatchSpec.fun2ms(fn {<<102, "o", 111, a::binary>>} -> a end)
    end

    test "can work with explicitly sized variables" do
      assert [
               {{:"$1"},
                [
                  {:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}},
                  {:"=:=", {:binary_part, :"$1", 3, 3}, {:const, "bar"}}
                ], [{:binary_part, :"$1", 3, 3}]}
             ] = MatchSpec.fun2ms(fn {<<"foo", a::binary-size(3), "bar">>} -> a end)
    end

    test "extra binary specifier on a string literal" do
      assert [
               {{:"$1"}, [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]}
             ] = MatchSpec.fun2ms(fn {<<"foo"::binary, a::binary>>} -> a end)
    end

    # note that this layout is extended into the above layout using `Macro.expand/2`
    # so it should generally work if everything above works.
    test "matching on binaries works" do
      assert [
               {
                 {:"$1"},
                 [{:"=:=", {:binary_part, :"$1", 0, 3}, {:const, "foo"}}],
                 [{:binary_part, :"$1", 3, {:-, {:byte_size, :"$1"}, 3}}]
               }
             ] ==
               MatchSpec.fun2ms(fn {"foo" <> a} -> a end)
    end
  end

  describe "result expressions" do
    test "can output arbitrary bindings" do
      assert [{{:"$1", :"$2", :"$3"}, [], [:"$3"]}] ==
               MatchSpec.fun2ms(fn {a, b, c} -> c end)
    end

    test "can output tuples" do
      assert [{{:"$1"}, [], [{{:"$1"}}]}] ==
               MatchSpec.fun2ms(fn {a} -> {a} end)
    end

    test "can output maps" do
      assert [{{:"$1", :"$2"}, [], [%{key: :"$1", value: :"$2"}]}] ==
               MatchSpec.fun2ms(fn {a, b} -> %{key: a, value: b} end)
    end

    test "can output structs" do
      assert [{{:"$1", :"$2"}, [], [%MyStruct{key: :"$1", value: :"$2"}]}] ==
               MatchSpec.fun2ms(fn {a, b} -> %MyStruct{key: a, value: b} end)
    end

    test "builtin custom guards work" do
      assert [{{:"$1"}, [], [{:andalso, {:is_integer, :"$1"}, {:==, {:band, :"$1", 1}, 0}}]}] ==
               MatchSpec.fun2ms(fn {a} -> Integer.is_even(a) end)
    end

    test "local custom guards work" do
      assert [{{:"$1"}, [], [{:"=:=", :"$1", 5}]}] ==
               MatchSpec.fun2ms(fn {a} -> is_five(a) end)
    end

    defguardp in_guard(x) when x in [:foo, :bar]

    test "local custom guard with `in` works" do
      assert [{{:"$1"}, [], [{:orelse, {:"=:=", :"$1", :foo}, {:"=:=", :"$1", :bar}}]}] ==
        MatchSpec.fun2ms(fn {a} -> in_guard(a) end)
    end
  end
end
