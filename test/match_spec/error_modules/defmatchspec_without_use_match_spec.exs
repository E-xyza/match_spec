defmodule MatchSpecTest.DefmatchspecWithoutUseMatchSpec do
  import MatchSpec

  defmatchspec my_matchspec(_) do
    _ -> true
  end
end
