# MatchSpec

![tests](https://github.com/e-xyza/match_spec/actions/workflows/test_flow.yml/badge.svg)

`:ets` matchspec helper library for elixir.  Exposes the `fun2ms/1` macro which 
transforms elixir-style function code into ets matchspecs.

```elixir
iex> require MatchSpec
iex> MatchSpec.fun2ms(fn {key, value} when key === :foo -> value end)
[{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}]
```

Also exposes the `ms2fun/2` function which converts a matchspec to function code
or ast which represents a function that performs the same task as the ets matchspec

```elixir
iex> MatchSpec.ms2fun([{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}], :code)
"fn {v1, v2} when v1 === :foo -> v2 end"
iex> :ets.test_ms({:foo, :bar}, MatchSpec.fun2ms(fn {key, value} when key === :foo -> value end))
{:ok, :bar}
```

Provides `fun2msfun/4` macro which can be used to parametrize the matchspec:

```elixir
iex> require MatchSpec
iex> lambda = MatchSpec.fun2msfun(fn {^key, value} -> value end, [key])
iex> lambda.(:key)
[{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :key}}], [:"$2"]}]
```

Provides `defmatchspec/2` and `defmatchspecp/2` macros which can be used to 
directly generate functions in your module

```elixir
defmodule MyModule do
  use MatchSpec
  
  defmatchspec my_matchspec(key) do
    {^key, value} -> value
  end
end

MyModule.my_matchspec(:key)
[{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :key}}], [:"$2"]}]
```

## Installation

The package can be installed by adding `match_spec` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:match_spec, "~> 0.2.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/match_spec>.