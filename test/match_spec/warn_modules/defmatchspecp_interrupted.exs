defmodule MatchSpecTest.DefmatchspecpInterrupted do
  use MatchSpec

  defmatchspecp(my_matchspec(:foo)(_), do: true)

  defmatchspecp(other_matchspec(:foo)(_), do: true)

  defmatchspecp(my_matchspec(:bar)(_), do: true)
end
