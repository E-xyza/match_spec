defmodule MatchSpecTest.DefmatchspecAfterDefmatchspecp do
  use MatchSpec

  defmatchspecp(my_matchspec(_)(_), do: true)

  defmatchspec(my_matchspec(_)(_), do: true)
end
