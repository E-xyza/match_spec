defmodule MatchSpec.Fun2ms.ConditionExpression do
  alias MatchSpec.Fun2ms
  alias MatchSpec.Tools
  import Tools

  @spec from_ast(Tools.when_ast() | Tools.expr_ast(), Fun2ms.t()) ::
          Tools.condition_ast() | Tools.body_ast()

  guards = [
    is_atom: 1,
    is_float: 1,
    is_integer: 1,
    is_list: 1,
    is_number: 1,
    is_pid: 1,
    is_port: 1,
    is_reference: 1,
    is_tuple: 1,
    is_map: 1,
    is_binary: 1,
    is_function: 1,
    not: 1,
    abs: 1,
    hd: 1,
    length: 1,
    map_size: 1,
    node: 0,
    round: 1,
    size: 1,
    bit_size: 1,
    byte_size: 1,
    tl: 1,
    trunc: 1,
    binary_part: 3,
    +: 2,
    -: 2,
    *: 2,
    div: 2,
    rem: 2,
    self: 0,
    >: 2,
    >=: 2,
    <: 2,
    ==: 2
  ]

  for {guard, arity} <- guards do
    def from_ast({unquote(guard), _, args}, state) when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &from_ast(&1, state))
      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  def from_ast({:is_map_key, _, [map, key]}, state) do
    # note in erlang is_map_key takes params (key, map)
    to_tuple_ast({:is_map_key, from_ast(key, state), from_ast(map, state)})
  end

  def from_ast({:elem, _, [tup, idx]}, state) do
    to_tuple_ast(
      case idx do
        int when is_integer(int) ->
          {:element, int + 1, from_ast(tup, state)}

        {_, _, _} ->
          {:element, to_tuple_ast({:+, from_ast(idx, state), 1}), from_ast(tup, state)}
      end
    )
  end

  # dot syntax for map dereferencing
  def from_ast({{:., _, [var, deref]}, _, []}, state) when is_atom(deref) do
    to_tuple_ast({:map_get, deref, from_ast(var, state)})
  end

  # guards with names that are different between matchspec and elixir
  for {exguard, {msguard, arity}} <- [
        and: {:andalso, 2},
        or: {:orelse, 2},
        <=: {:"=<", 2},
        ===: {:"=:=", 2},
        !=: {:"/=", 2},
        !==: {:"=/=", 2},
        # multiple when clauses in a match are equivalent to "or" 🤯
        when: {:orelse, 2}
      ] do
    def from_ast({unquote(exguard), _, args}, state)
        when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &from_ast(&1, state))
      to_tuple_ast([unquote(msguard) | translated_args])
    end
  end

  # direct usage of erlang guards
  erlangfunctions =
    guards ++
      [
        is_map_key: 2,
        is_record: 2,
        and: 2,
        or: 2,
        element: 1,
        map_get: 2,
        andalso: 2,
        orelse: 2,
        band: 2,
        bor: 2,
        bxor: 2,
        bnot: 2,
        bsl: 2,
        bsr: 2,
        "=<": 2,
        "=:=": 2,
        "/=": 2,
        "=/=": 2
      ]

  for {guard, arity} <- erlangfunctions do
    def from_ast({{:., _, [:erlang, unquote(guard)]}, _, args}, state)
        when length(args) == unquote(arity) do
      translated_args = Enum.map(args, &from_ast(&1, state))

      to_tuple_ast([unquote(guard) | translated_args])
    end
  end

  # specal case the `in` macro
  def from_ast({:in, _, [left, var]}, state)
      when is_var_ast(var) and is_var_ast(:erlang.map_get(var_name(var), state.bindings)) do
    left_expr = from_ast(left, state)

    quote do
      unquote(var)
      |> Enum.map(&{:"=:=", unquote(left_expr), {:const, &1}})
      |> Enum.reduce(&{:orelse, &1, &2})
    end
  end

  def from_ast({var, _, tag}, state) when is_atom(tag) do
    case Map.fetch!(state.bindings, var) do
      :"$_" ->
        :"$_"

      int when is_integer(int) ->
        :"$#{int}"

      var when is_var_ast(var) ->
        {:const, var}

      {:external, {k, context}} ->
        {k, [], context}

      part = {:{}, _, [:binary_part | _]} ->
        part
    end
  end

  # tuples
  def from_ast({a, b}, state) do
    [a, b]
    |> Enum.map(&from_ast(&1, state))
    |> tuple_wrap
  end

  def from_ast({:{}, _, tuple_parts}, state) do
    tuple_parts
    |> Enum.map(&from_ast(&1, state))
    |> tuple_wrap
  end

  # maps
  def from_ast({:%{}, _, map_parts}, state) do
    parts = Enum.map(map_parts, fn {k, v} -> {k, from_ast(v, state)} end)
    {:%{}, [], parts}
  end

  # structs
  def from_ast({:%, _, [alias_part, map_part]}, state) do
    {:%, [], [alias_part, from_ast(map_part, state)]}
  end

  def from_ast(atom, _state) when is_atom(atom) do
    case Atom.to_string(atom) do
      "$" <> _ -> {:const, atom}
      _ -> atom
    end
  end

  def from_ast(number, _state) when is_number(number), do: number

  @part_name %{when: "when clause", expr: "result expression"}

  def from_ast(call = {_, _, args}, state) when is_list(args) do
    case Macro.expand(call, %{state.caller | context: :guard}) do
      ^call ->
        part_name = Map.fetch!(@part_name, state.in)

        raise CompileError,
          description:
            "non-guard or local guard function found in #{part_name}: `#{Macro.to_string(call)}`",
          file: state.caller.file,
          line: state.caller.line

      guard ->
        from_ast(guard, state)
    end
  end
end
