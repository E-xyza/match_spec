defmodule MatchSpec.Ms2fun do
  defstruct needs_tuple: false, vars: []

  def to_fun(branches, :ast) do
    {:fn, [], Enum.map(branches, &branches_to_arrows/1)}
  end

  def to_fun(match_spec, :code) do
    match_spec
    |> to_fun(:ast)
    |> Macro.to_string()
  end

  defp branches_to_arrows({match, filters, [body]}) do
    {predicate!, state!} = predicate_from_match(match, %__MODULE__{})
    {guards, state!} = Enum.map_reduce(filters, state!, &guard_from_filter/2)
    {body_ast, state!} = body_from(body, state!)

    predicate! =
      if state!.needs_tuple && (predicate! != var(:tuple)) do
        {:=, [], [var(:tuple), predicate!]}
      else
        predicate!
      end

    predicate! = case guards do
      [] -> predicate!
      _ -> {:when, [], [predicate!, when_clauses(guards)]}
    end

    {:->, [], [[predicate!], body_ast]}
  end

  defp when_clauses([singleton]), do: singleton
  defp when_clauses([lhs, rhs]), do: {:when, [], [lhs, rhs]}
  defp when_clauses([head | rest]), do: {:when, [], [head, when_clauses(rest)]}

  defp var(name) when is_atom(name), do: {name, [], nil}
  defp var(int) when is_number(int), do: var(:"v#{int}")

  defp predicate_from_match(:"$_", state), do: {var(:tuple), %{state | needs_tuple: true}}
  defp predicate_from_match(:_, state), do: {var(:_), state}

  defp predicate_from_match(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &predicate_from_match/2)
  end

  defp predicate_from_match(atom, state) when is_atom(atom) do
    with "$" <> number <- Atom.to_string(atom),
         {int, _} <- Integer.parse(number) do
      {var(int), %{state | vars: [int | state.vars]}}
    else
      # TODO: better error handling
      _ -> raise "oops"
    end
  end

  defp predicate_from_match(tuple, state) when is_tuple(tuple) do
    {tuple_list, new_state} =
      tuple
      |> Tuple.to_list()
      |> Enum.map_reduce(state, &predicate_from_match/2)

    {{:{}, [], tuple_list}, new_state}
  end

  defp predicate_from_match(map = %struct{}, state) do
    {predicate, new_state} = predicate_from_match(Map.from_struct(map), state)

    {{:%, [], [struct, predicate]}, new_state}
  end

  defp predicate_from_match(map, state) when is_map(map) do
    {map_list, new_state} =
      Enum.map_reduce(map, state, fn
        {k, v}, state_so_far ->
          {new_v, new_state} = predicate_from_match(v, state_so_far)
          {{k, new_v}, new_state}
      end)

    {{:%{}, [], map_list}, new_state}
  end

  defp predicate_from_match(literal, state) when is_number(literal) or is_bitstring(literal) do
    {literal, state}
  end

  # arity-0 guards
  arity_0_guards = [:node, :self]

  for guard <- arity_0_guards do
    defp guard_from_filter({unquote(guard)}, state) do
      {{unquote(guard), [], []}, state}
    end
  end

  # arity-1 guards
  arity_1_guards =
    ~w(is_atom is_float is_integer is_list is_number is_pid is_port is_reference is_tuple is_map is_binary is_function not map_size abs hd length round size bit_size byte_size tl trunc)a

  for guard <- arity_1_guards do
    defp guard_from_filter({unquote(guard), v1}, state) do
      {v1_ast, new_state} = guard_from_filter(v1, state)
      {{unquote(guard), [], [v1_ast]}, new_state}
    end
  end

  arity_2_guards = ~w(is_record + - * div rem > >= < ==)a

  for guard <- arity_2_guards do
    defp guard_from_filter({unquote(guard), v1, v2}, state) do
      {asts, new_state} = Enum.map_reduce([v1, v2], state, &guard_from_filter/2)
      {{unquote(guard), [], asts}, new_state}
    end
  end

  erlang_arity_2_guards = ~w(is_record map_get and or xor band bor bxor bnot bsl bsr)a

  for guard <- erlang_arity_2_guards do
    defp guard_from_filter({unquote(guard), v1, v2}, state) do
      {asts, new_state} = Enum.map_reduce([v1, v2], state, &guard_from_filter/2)
      {{{:., [], [:erlang, unquote(guard)]}, [], asts}, new_state}
    end
  end

  renamed = [andalso: :and, orelse: :or, "=<": :<=, "=:=": :===, "=/=": :!==, "/=": :!=]
  for {erguard, exguard} <- renamed do
    defp guard_from_filter({unquote(erguard), v1, v2}, state) do
      {asts, new_state} = Enum.map_reduce([v1, v2], state, &guard_from_filter/2)
      {{unquote(exguard), [], asts}, new_state}
    end
  end

  # unusual guards
  defp guard_from_filter({:is_map_key, v1, v2}, state) do
    # note the order is reversed!
    {asts, new_state} = Enum.map_reduce([v2, v1], state, &guard_from_filter/2)
    {{:is_map_key, [], asts}, new_state}
  end

  defp guard_from_filter({:binary_part, v1, v2, v3}, state) do
    {asts, new_state} = Enum.map_reduce([v1, v2, v3], state, &guard_from_filter/2)
    {{:binary_part, [], asts}, new_state}
  end

  defp guard_from_filter({:element, v1, v2}, state) do
    {[v1_ast, v2_ast], new_state} = Enum.map_reduce([v1, v2], state, &guard_from_filter/2)
    case v2 do
      int when is_integer(int) ->
        {{:elem, [], [v1_ast, v2 - 1]}, new_state}
      _ ->
        {{:elem, [], [v1_ast, {:-, [], [v2_ast, 1]}]}, new_state}
    end
  end

  defp guard_from_filter(:"$_", state), do: {var(:tuple), %{state | needs_tuple: true}}
  defp guard_from_filter(:"$$", state), do: {splat(state), state}

  defp guard_from_filter(atom, state) when is_atom(atom) do
    with "$" <> number <- Atom.to_string(atom),
         {int, _} <- Integer.parse(number) do
      {var(int), state}
    else
      # TODO: better error handling
      _ -> raise "oops"
    end
  end

  defp guard_from_filter(number, state) when is_number(number) do
    {number, state}
  end

  defp body_from(:"$_", state), do: {var(:tuple), %{state | needs_tuple: true}}
  defp body_from(:"$$", state), do: {splat(state), state}

  defp body_from(atom, state) when is_atom(atom) do
    with "$" <> number <- Atom.to_string(atom),
         {int, _} <- Integer.parse(number) do
      {var(int), state}
    else
      _ -> {atom, state}
    end
  end

  defp splat(state) do
    state.vars
    |> Enum.sort()
    |> Enum.map(&var/1)
  end
end
