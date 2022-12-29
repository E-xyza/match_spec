defmodule MatchSpecTest.DefmatchspecAfterDefmatchspecp do
  use MatchSpec

  defmatchspecp my_matchspec(_) do
    _ -> true
  end

  defmatchspec my_matchspec(_) do
    _ -> true
  end
end
