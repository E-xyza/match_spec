defmodule MatchSpec.Tools do
  @moduledoc false

  @doc """
  guard that returns the variable name of a variable.
  """
  defguard var_name(var) when elem(var, 0)

  @doc """
  guard that tests for whether or not the ast represents a variable.
  """
  defguard is_var_ast(var)
           when is_tuple(var) and tuple_size(var) == 3 and is_atom(var_name(var)) and
                  is_list(elem(var, 1)) and
                  is_atom(elem(var, 2))

  @typedoc """
  type that represents the ast of a variable macro.
  """
  @type var_ast :: {atom, keyword, nil | module}

  @typedoc """
  type that represents how we will access a variable.

  - if value is an integer, that means the variable can be accessed as :"$<integer>"
  - if value is :"$_" that means it is bound as the full match.
  - if value is a macro, that means one of two things
    - it is bound as variable from the matchspec function
    - it is part of a string matcher and may have ast as part of its evaluation.
  """
  @type bindings :: %{optional(atom) => pos_integer | :"$_" | var_ast}

  @typedoc """
  represents pins.

  This could be a variable ast, or possibly a directive to match a variable against
  a string literal, for string matching.
  """
  @type pins :: %{
          optional(atom) => var_ast,
          optional(Macro.t()) => {:const, String.t() | var_ast}
        }

  # UTILITY functions
  @spec binding_list(bindings) :: String.t()
  def binding_list(bindings) do
    bindings
    |> Enum.flat_map(fn {key, value} ->
      List.wrap(if is_var_ast(value), do: "#{key}")
    end)
    |> inspect
  end

  # two-tuples are special cases.
  @spec to_tuple_ast(tuple) :: Macro.t()
  def to_tuple_ast(tuple = {_, _}), do: tuple

  def to_tuple_ast(tuple) when is_tuple(tuple) do
    {:{}, [], Tuple.to_list(tuple)}
  end

  def to_tuple_ast(list) when is_list(list) do
    {:{}, [], list}
  end

  @spec tuple_wrap(list) :: Macro.t()
  def tuple_wrap(tuple_parts) do
    tuple_parts
    |> List.to_tuple()
    |> to_tuple_ast
    |> List.wrap()
    |> List.to_tuple()
    |> to_tuple_ast
  end

  def macro_inspect(macro) do
    macro
    |> Macro.to_string()
    |> IO.puts()

    macro
  end
end
