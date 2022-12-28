defmodule MatchSpecTest.DefmatchspecpWithoutUseMatchSpec do
  import MatchSpec

  defmatchspecp(my_matchspec()(_), do: true)
end
