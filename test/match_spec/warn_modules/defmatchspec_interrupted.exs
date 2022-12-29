defmodule MatchSpecTest.DefmatchspecInterrupted do
  use MatchSpec

  defmatchspec(my_matchspec(:foo)(_), do: true)

  defmatchspec(other_matchspec(:foo)(_), do: true)

  defmatchspec(my_matchspec(:bar)(_), do: true)
end
