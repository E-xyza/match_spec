defmodule MatchSpecTest.DefmatchspecpAfterDefmatchspec do
  use MatchSpec

  defmatchspec(my_matchspec(_)(_), do: true)

  defmatchspecp(my_matchspec(_)(_), do: true)
end
