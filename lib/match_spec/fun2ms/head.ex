defmodule MatchSpec.Fun2ms.Head do
  @moduledoc false

  alias MatchSpec.Fun2ms.BinaryMatch
  alias MatchSpec.Tools
  import Tools

  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  @enforce_keys [:caller, :bindings]
  defstruct @enforce_keys ++
              [:top_pin, :arg_match_ast, head_ast: :_, pins: %{}, preflight_checks: []]

  @type state :: %__MODULE__{
          head_ast: Macro.t(),
          # the ast of whatever code resulted in head_ast
          arg_match_ast: nil | Macro.t(),
          top_pin: nil | Tools.var_ast(),
          pins: Tools.pins(),
          caller: Macro.Env.t(),
          bindings: Tools.bindings(),
          preflight_checks: [Macro.t()]
        }

  @spec from_arg_ast(Macro.t(), Macro.Env.t()) :: state

  def from_arg_ast(arg_ast, bindings \\ %{}, caller) do
    parse_top(arg_ast, %__MODULE__{bindings: bindings, caller: caller})
  end

  @spec parse_top(Macro.t(), state) :: state
  def parse_top({:=, _, matches}, state) do
    Enum.reduce(matches, state, &parse_top/2)
  end

  # disallowed top types: struct, map, list, binary
  def parse_top(top = {:%, _, _}, %{caller: caller}) do
    raise CompileError,
      description: "top match cannot be a struct (got: #{Macro.to_string(top)})",
      file: caller.file,
      line: caller.line
  end

  def parse_top(top = {:%{}, _, _}, %{caller: caller}) do
    raise CompileError,
      description: "top match cannot be a map (got: #{Macro.to_string(top)})",
      file: caller.file,
      line: caller.line
  end

  def parse_top(top, %{caller: caller}) when is_list(top) do
    raise CompileError,
      description: "top match cannot be a list (got: #{Macro.to_string(top)})",
      file: caller.file,
      line: caller.line
  end

  def parse_top(top = {:<<>>, _, _}, %{caller: caller}) do
    raise CompileError,
      description: "top match cannot be a binary (got: #{Macro.to_string(top)})",
      file: caller.file,
      line: caller.line
  end

  def parse_top(head_ast = {:^, _, [var]}, state)
      when is_var_ast(var) do
    name = var_name(var)
    verify_pattern_unique!(head_ast, state)
    verify_pin!(name, state)

    state
    |> set_top_pin(head_ast)
    |> add_to_pins(:"$_", var)
    |> add_preflight_check(tuple_check(var))
  end

  def parse_top(var, state) when is_var_ast(var) do
    name = var_name(var)

    if Map.has_key?(state.bindings, name) do
      IO.warn("unpinned variable `#{name}` in function match head has the same name as a binding")
    end

    case Atom.to_string(name) do
      "_" <> _ -> state
      _ -> add_to_bindings(state, name, :"$_")
    end
  end

  # twoples are a special case
  def parse_top(arg_ast = {_, _}, state) do
    verify_pattern_unique!(arg_ast, state)

    {head_ast, new_state} = parse_structured(arg_ast, state)
    %{new_state | head_ast: head_ast, arg_match_ast: arg_ast}
  end

  # generic tuples
  def parse_top(tuple_ast = {:{}, _, _}, state) do
    verify_pattern_unique!(tuple_ast, state)

    {head_ast, new_state} = parse_structured(tuple_ast, state)
    %{new_state | head_ast: head_ast, arg_match_ast: tuple_ast}
  end

  def parse_top(disallowed_ast, %{caller: caller}) do
    raise CompileError,
      description: "top match must be a tuple (got: #{Macro.to_string(disallowed_ast)})",
      file: caller.file,
      line: caller.line
  end

  # handle pins
  def parse_structured({:^, _, [var]}, state = %{caller: caller, bindings: bindings})
      when is_var_ast(var) do
    name = var_name(var)

    index =
      case Map.fetch(bindings, name) do
        {:ok, index} when is_integer(index) ->
          index

        {:ok, {^name, _, _}} ->
          lowest_index(bindings)

        _ ->
          raise CompileError,
            description:
              "pin requires a bound variable (got `#{name}`, found: #{binding_list(bindings)})",
            file: caller.file,
            line: caller.line
      end

    match_var = :"$#{index}"

    new_state =
      state
      |> add_to_pins(match_var, var)
      # this overwrites the `name` binding.
      |> add_to_bindings(name, index)

    {match_var, new_state}
  end

  # handle vars
  def parse_structured(var, state) when is_var_ast(var) do
    name = var_name(var)
    index = maybe_new_binding_for(name, state)

    case Atom.to_string(name) do
      "_" <> _ -> {:_, state}
      _ -> {:"$#{index}", add_to_bindings(state, name, index)}
    end
  end

  # twoples are a special case
  def parse_structured({a, b}, state) do
    {head_ast_list, new_state} = Enum.map_reduce([a, b], state, &parse_structured/2)
    {List.to_tuple(head_ast_list), new_state}
  end

  def parse_structured(ast = {:<>, _, _}, state) do
    # convert <> operators to <<>> operations
    ast
    |> Macro.expand(state.caller)
    |> parse_structured(state)
  end

  def parse_structured({:<<>>, _, parts}, state) do
    BinaryMatch.from_parts(parts, state)
  end

  # general call structures
  def parse_structured({call, meta, args}, state) do
    {head_ast_list, new_state} = Enum.map_reduce(args, state, &parse_structured/2)
    {{call, meta, head_ast_list}, new_state}
  end

  def parse_structured([], state), do: {[], state}

  def parse_structured([head | rest], state) do
    {[head_ast, rest_ast], new_state} = Enum.map_reduce([head, rest], state, &parse_structured/2)
    {[head_ast | rest_ast], new_state}
  end

  def parse_structured(literal, state)
      when is_number(literal) or is_atom(literal) or is_binary(literal) do
    {literal, state}
  end

  defp verify_pattern_unique!(_, %{head_ast: head_ast, top_pin: top_pin})
       when head_ast === :_ and is_nil(top_pin),
       do: :ok

  defp verify_pattern_unique!(
         current_ast,
         %{arg_match_ast: match_ast, caller: %{file: file, line: line}, top_pin: top_pin}
       ) do
    # convert this into a usable ast
    {initial_message, previous_ast} =
      case {current_ast, top_pin} do
        {{:^, _, _}, nil} ->
          {"cannot use a pin in the same head as a structured pattern match, found", match_ast}

        {{:^, _, _}, _} ->
          {"only one pin is allowed in the head, multiple pins found", top_pin}

        {_, nil} ->
          {"only one structured pattern match allowed in the head, multiple patterns found",
           match_ast}

        _ ->
          {"cannot use a pin in the same head as a structured pattern match, found", top_pin}
      end

    [previous_code, current_code] = Enum.map([previous_ast, current_ast], &Macro.to_string/1)

    raise CompileError,
      description: "#{initial_message}: `#{previous_code}` and `#{current_code}`",
      file: file,
      line: line
  end

  defp verify_pin!(name, %{bindings: bindings, caller: caller}) do
    unless Map.has_key?(bindings, name) do
      raise CompileError,
        description:
          "pin requires a bound variable (got `#{name}`, found: #{binding_list(bindings)})",
        file: caller.file,
        line: caller.line
    end

    :ok
  end

  @spec maybe_new_binding_for(atom, state) :: non_neg_integer
  defp maybe_new_binding_for(name, %{bindings: bindings}) do
    case bindings do
      %{^name => value} when is_integer(value) ->
        value

      %{^name => tuple} when is_tuple(tuple) ->
        IO.warn(
          "unpinned variable `#{name}` in function match head has the same name as a binding"
        )

        lowest_index(bindings)

      _ ->
        lowest_index(bindings)
    end
  end

  @spec lowest_index(Tools.bindings()) :: non_neg_integer
  def lowest_index(bindings) do
    bindings
    |> Map.values()
    |> Enum.reject(&(match?({_, _, _}, &1) or &1 == :"$_"))
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  # reducers

  defp set_top_pin(state, top_pin) do
    %{state | top_pin: top_pin}
  end

  # preflight checks

  defp tuple_check(var) do
    quote bind_quoted: [var: var] do
      unless is_tuple(var) do
        raise ArgumentError,
              "matching against the whole match must be a tuple, got pinned value `#{inspect(var)}`"
      end
    end
  end
end
