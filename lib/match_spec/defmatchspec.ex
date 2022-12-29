defmodule MatchSpec.Defmatchspec do
  @moduledoc false

  # this module contains the (private) struct that is used to keep track of
  # defmatchspec and defmatchspecp definitions

  # to make debugging less insane
  @derive {Inspect, except: [:caller]}
  defstruct [:name, :type, :arity, :bindings, :arg_ast, :when_ast, :expr_ast, :caller]

  defmacro __before_compile__(env) do
    env.module
    |> Module.get_attribute(:match_spec_bodies)

    quote do
      require MatchSpec
    end
  end

  def struct_from(type, {{name, _, bindings}, _, arg}, expr, caller) do
    %__MODULE__{
      name: name,
      type: type,
      arity: length(bindings),
      bindings: bindings,
      arg_ast: arg,
      when_ast: [],
      expr_ast: expr,
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
end
