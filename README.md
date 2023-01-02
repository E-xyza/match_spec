# MatchSpec

![tests](https://github.com/e-xyza/match_spec/actions/workflows/test_flow.yml/badge.svg)

ets matchspec helper library for elixir.  Exposes fun2ms and ms2fun functions which transform
elixir-style functions into erlang matchspecs.

```elixir
iex> require MatchSpec
iex> MatchSpec.fun2ms(fn {key, value} when key === :foo -> value end)
[{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}]
iex> MatchSpec.ms2fun([{{:"$1", :"$2"}, [{:"=:=", :"$1", {:const, :foo}}], [:"$2"]}], :code)
"fn {v1, v2} when v1 === :foo -> v2 end"
iex> :ets.test_ms({:foo, :bar}, MatchSpec.fun2ms(fn {key, value} when key === :foo -> value end))
{:ok, :bar}
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

