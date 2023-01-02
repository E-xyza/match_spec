defmodule MatchSpec.Fun2ms.BinaryMatch do
  @moduledoc false
  alias MatchSpec.Fun2ms.Head
  alias MatchSpec.Tools

  import Tools

  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  @enforce_keys [:ms_var, :caller, :bindings]
  defstruct @enforce_keys ++ [pins: %{}, bytes: 0, free_match: nil, preflight_checks: []]

  @type state :: %__MODULE__{
          ms_var: atom,
          caller: Macro.Env.t(),
          bindings: Tools.bindings(),
          pins: Tools.pins(),
          bytes: Macro.t(),
          free_match: Macro.t(),
          preflight_checks: [Macro.t()]
        }

  @spec from_parts([Macro.t()], Head.state()) :: {atom, Head.state()}
  def from_parts(parts, head_state) do
    index = Head.lowest_index(head_state.bindings)
    ms_var = :"$#{index}"

    parts_state =
      parts
      |> consolidate
      |> Enum.reduce(from_head_state(head_state, ms_var), &from_part/2)

    new_state =
      Enum.reduce(
        ~w(bindings pins preflight_checks)a,
        head_state,
        fn key, head_state_so_far ->
          Map.update(head_state_so_far, key, nil, &Enum.into(Map.get(parts_state, key), &1))
        end
      )

    {ms_var, new_state}
  end

  @spec from_head_state(Head.state(), atom) :: state
  defp from_head_state(head_state, ms_var) do
    %__MODULE__{ms_var: ms_var, caller: head_state.caller, bindings: head_state.bindings}
  end

  @binary_synonyms ~w(binary bytes utf8)a

  defguardp is_ast(tuple) when tuple_size(tuple) === 3

  defguardp is_qualifier(tuple)
            when is_ast(tuple) and
                   is_atom(elem(tuple, 0)) and
                   (is_atom(elem(tuple, 2)) or
                      elem(tuple, 2) === [])

  defguardp is_valid(tuple) when is_qualifier(tuple) and var_name(tuple) in @binary_synonyms

  defp from_part(_, %{free_match: free_match, caller: caller}) when not is_nil(free_match) do
    # once we have a free match, we can't have any other parts.
    raise CompileError,
      description:
        "a binary match without size (found `#{Macro.to_string(free_match)}`) is only allowed at the end of a binary pattern",
      line: caller.line,
      file: caller.file
  end

  defp from_part(binary, state) when is_binary(binary) do
    size = byte_size(binary)
    pin_part = to_tuple_ast({:binary_part, state.ms_var, state.bytes, size})

    state
    |> add_to_pins(pin_part, binary)
    |> add_to_bytes(size)
  end

  defp from_part({:"::", _, [binary, binary_qualifier]}, state)
       when is_binary(binary) and is_valid(binary_qualifier) do
    from_part(binary, state)
  end

  defp from_part({:"::", _, [binary, compound_qualifier = {:-, _, _}]}, state)
       when is_binary(binary) do
    validate_compound_for_literal!(compound_qualifier, state)
    from_part(binary, state)
  end

  # qualified matches
  defp from_part({:"::", _, [var, segment_type]}, state)
       when is_var_ast(var) and is_valid(segment_type) do
    name = var_name(var)
    size = to_tuple_ast({:-, {:byte_size, state.ms_var}, state.bytes})
    tuple_ast = to_tuple_ast({:binary_part, state.ms_var, state.bytes, size})

    state
    |> add_to_bindings(name, tuple_ast)
    |> set_free_match(var)
  end

  @empty_qualifier %{type: false, size: nil}

  defp from_part(pin = {:"::", _, [var, qualifier = {:-, _, _}]}, state = %{caller: caller})
       when is_var_ast(var) do
    %{type: has_type, size: size_ast} = scan_qualifiers(qualifier, @empty_qualifier, caller)

    unless has_type do
      code = Macro.to_string(pin)

      raise CompileError,
        description:
          "invalid segment type, must have the type `binary`, `bytes`, or `utf8`: got `#{code}`",
        file: caller.file,
        line: caller.line
    end

    free_match = unless size_ast, do: var
    name = var_name(var)
    tuple_ast = to_tuple_ast({:binary_part, state.ms_var, state.bytes, size_ast})

    state
    |> add_to_bindings(name, tuple_ast)
    |> set_free_match(free_match)
  end

  # pins
  defp from_part(
         pin = {:"::", _, [{:^, _, [var]}, qualifier = {:-, _, _}]},
         state = %{caller: caller}
       )
       when is_var_ast(var) do
    validate_variable_bound!(var_name(var), state)

    %{type: has_type, size: size_ast} = scan_qualifiers(qualifier, @empty_qualifier, caller)

    unless has_type do
      code = Macro.to_string(pin)

      raise CompileError,
        description:
          "invalid segment type, must have the type `binary`, `bytes`, or `utf8`: got `#{code}`",
        file: caller.file,
        line: caller.line
    end

    unless size_ast do
      code = Macro.to_string(pin)

      suggestion =
        Macro.to_string(
          quote do
            ^unquote(var) :: binary - size(byte_size(unquote(var)))
          end
        )

      raise CompileError,
        description:
          "invalid segment type, a pinned variable must have a size specifier.  Try `#{suggestion}` in place of `#{code}`",
        file: caller.file,
        line: caller.line
    end

    tuple_ast = to_tuple_ast({:binary_part, state.ms_var, state.bytes, size_ast})

    state
    |> add_to_pins(tuple_ast, var)
    |> add_to_bytes(size_ast)
    |> add_preflight_check(binary_preflight_check(var))
    |> add_preflight_check(length_preflight_check(var, size_ast))
  end

  # error conditions
  defp from_part(var, %{caller: caller}) when is_var_ast(var) do
    raise CompileError,
      description:
        "invalid segment, the match variable (`#{var_name(var)}`) must be typed `binary`, `bytes`, or `utf8`",
      file: caller.file,
      line: caller.line
  end

  defp from_part({:"::", _, [var, type = {name, _, _}]}, %{caller: caller})
       when is_var_ast(var) and is_ast(type) do
    raise CompileError,
      description: "invalid segment type, must be `binary`, `bytes`, or `utf8`: got `#{name}`",
      file: caller.file,
      line: caller.line
  end

  defp from_part(pin = {:^, _, [var]}, state = %{caller: caller}) when is_var_ast(var) do
    validate_variable_bound!(var_name(var), state)
    quoted_pin = Macro.to_string(pin)

    quoted_suggestion =
      Macro.to_string(
        quote do
          unquote(pin) :: binary - size(byte_size(unquote(var)))
        end
      )

    raise CompileError,
      description:
        "invalid segment type, a pinned variable must have a type and size specifier.  Try `#{quoted_suggestion}` in place of `#{quoted_pin}`",
      file: caller.file,
      line: caller.line
  end

  defp from_part(pin = {:"::", _, [inner = {:^, _, [var]}, segment_spec]}, %{caller: caller})
       when is_var_ast(var) and is_valid(segment_spec) do
    quoted_pin = Macro.to_string(pin)

    quoted_suggestion =
      Macro.to_string(
        {:"::", elem(pin, 1),
         [
           inner,
           quote do
             unquote(segment_spec) - size(byte_size(unquote(var)))
           end
         ]}
      )

    raise CompileError,
      description:
        "invalid segment type, a pinned variable must have a size specifier.  Try `#{quoted_suggestion}` in place of `#{quoted_pin}`",
      file: caller.file,
      line: caller.line
  end

  defp scan_qualifiers({:-, _, parts}, state, caller) do
    Enum.reduce(parts, state, &scan_qualifiers(&1, &2, caller))
  end

  defp scan_qualifiers(ast, state, _caller) when is_valid(ast), do: %{state | type: true}

  defp scan_qualifiers({:size, _state, [size_ast]}, state, _caller), do: %{state | size: size_ast}

  defp scan_qualifiers(other_ast, _state, caller) do
    raise CompileError,
      description: "unsupported binary match qualifier found: #{Macro.to_string(other_ast)}",
      line: caller.line,
      file: caller.file
  end

  defp validate_variable_bound!(var_name, %{caller: caller, bindings: bindings}) do
    case bindings do
      %{^var_name => {_, _, _}} ->
        :ok

      _ ->
        raise CompileError,
          description:
            "pin requires a bound variable (got `#{var_name}`, found: #{binding_list(bindings)})",
          line: caller.line,
          file: caller.file
    end
  end

  defp validate_compound_for_literal!({:-, _, parts}, state = %{caller: caller}) do
    Enum.each(parts, fn
      part = {:-, _, _} ->
        validate_compound_for_literal!(part, state)

      part when is_valid(part) ->
        :ok

      part ->
        part_str = Macro.to_string(part)

        raise CompileError,
          description:
            "invalid segment type or option for binary literal, must be `binary`, `bytes`, or `utf`: got `#{part_str}`",
          line: caller.line,
          file: caller.file
    end)
  end

  # NB: this function does not to be optimized with tail-call.  We generally
  # expect the binary parts list to be relatively small, and this step only
  # happens at compile-time.

  defguardp is_consolidatable(x) when is_binary(x) or is_integer(x)

  defp consolidate([first, next | rest])
       when is_consolidatable(first) and is_consolidatable(next) do
    consolidate([wrap(first) <> wrap(next) | rest])
  end

  defp consolidate([other | rest]) do
    [other | consolidate(rest)]
  end

  defp consolidate([]), do: []

  defp wrap(integer) when is_integer(integer), do: <<integer>>
  defp wrap(binary), do: binary

  # reducers
  @spec add_to_bytes(state, Macro.t()) :: state
  defp add_to_bytes(state, bytes), do: %{state | bytes: add_to(state.bytes, bytes)}

  @spec set_free_match(state, Macro.t()) :: state
  defp set_free_match(state, free_match) do
    %{state | free_match: free_match}
  end

  @spec add_to(Macro.t(), Macro.t()) :: Macro.t()
  defp add_to(int1, int2) when is_integer(int1) and is_integer(int2), do: int1 + int2
  defp add_to(0, ast), do: ast

  defp add_to(ast1, ast2) do
    quote do
      unquote(ast1) + unquote(ast2)
    end
  end

  defp binary_preflight_check(var) do
    name = var_name(var)

    quote bind_quoted: [var: var, name: name] do
      unless is_binary(var) do
        raise ArgumentError,
          message: "the variable `#{name}` is required to be a binary, got #{inspect(var)}"
      end
    end
  end

  defp length_preflight_check(var, {:byte_size, _, [var]}), do: nil

  defp length_preflight_check(var, length) do
    name = var_name(var)

    quote bind_quoted: [var: var, name: name, length: length] do
      size = byte_size(var)
      if size < length do
        raise ArgumentError,
          message:
            "the variable `#{name}` is expected to have length at least #{length}, got #{size}"
      end
    end
  end
end
