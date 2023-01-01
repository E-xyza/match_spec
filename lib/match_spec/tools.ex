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
  - if value is a macro, that means it is bound as variable from the matchspec function
  """
  @type bindings :: %{optional(atom) => pos_integer | :"$_" | var_ast}

  @typedoc """
  represents pins;
  """
  @type pins :: %{optional(atom) => var_ast}
end
