defmodule MatchSpec.Defmatchspec do
  @moduledoc false

  # this module contains the (private) struct that is used to keep track of
  # defmatchspec and defmatchspecp definitions

  alias MatchSpec.Fun2ms
  alias MatchSpec.Tools

  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  @enforce_keys [:name, :type, :arity, :bindings, :header, :arrows, :caller]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: atom,
          type: :def | :defp,
          arity: arity(),
          bindings: [Macro.t()],
          header: Macro.t(),
          arrows: [Macro.t()],
          caller: Macro.Env.t()
        }

  defmacro __before_compile__(env) do
    matchspec_functions =
      env.module
      |> Module.get_attribute(:match_spec_bodies)
      |> Enum.reverse()
      |> Enum.map(&to_function_body/1)

    quote do
      require MatchSpec
      unquote(matchspec_functions)
    end
  end

  def struct_from(type, header = {:when, _, [name_bindings, _guard]}, arrows, caller) do
    type
    |> struct_from(name_bindings, arrows, caller)
    |> Map.put(:header, header)
  end

  def struct_from(type, header = {name, _, bindings}, arrows, caller) do
    %__MODULE__{
      name: name,
      type: type,
      arity: length(bindings),
      bindings: Tools.vars_in(bindings),
      header: header,
      arrows: arrows,
      caller: caller
    }
  end

  def assert_used(env, type) do
    unless Module.get_attribute(env.module, :match_spec_bodies) do
      raise CompileError,
        description: "#{type} may only be used if you have `use MatchSpec` in the module",
        file: env.file,
        line: env.line
    end
  end

  @other_type %{def: :defp, defp: :def}
  @matchspec_name %{def: :defmatchspec, defp: :defmatchspecp}

  @doc false
  def assert_consistent(body, previous_bodies) do
    # note that accumulating attributes push to the front of the list
    prev_body = List.first(previous_bodies)

    if prev_body && !signatures_match?(body, prev_body) do
      other_type = @other_type[body.type]
      # check to see if we've previously defined it as the opposite type.
      if previous = Enum.find(previous_bodies, &signatures_match?(&1, %{body | type: other_type})) do
        # complain that we're trying to redefine something as an other type.
        other_typename = @matchspec_name[other_type]

        raise CompileError,
          description:
            "#{@matchspec_name[body.type]} #{body.name}/#{body.arity} was already been defined as #{other_typename} in #{previous.caller.file}:#{previous.caller.line}",
          line: body.caller.line,
          file: body.caller.file
      end

      if Enum.any?(previous_bodies, &signatures_match?(body, &1)) do
        IO.warn(
          "clauses with the same name and arity (number of arguments) should be grouped together, \"#{@matchspec_name[body.type]} #{body.name}/#{body.arity}\" was previously defined"
        )
      end
    end
  end

  @signature ~w(name type arity)a
  defp signatures_match?(a, b) do
    Map.take(a, @signature) == Map.take(b, @signature)
  end

  defp to_function_body(body) do
    matchspec_ast = Fun2ms.from_arrows(body.arrows, caller: body.caller, bind: body.bindings)

    quote do
      unquote(body.type)(unquote(body.header)) do
        unquote(matchspec_ast)
      end
    end
  end
end
