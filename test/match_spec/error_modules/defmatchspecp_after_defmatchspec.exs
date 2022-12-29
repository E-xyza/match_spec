defmodule MatchSpecTest.DefmatchspecpAfterDefmatchspec do
  use MatchSpec

  defmatchspec my_matchspec(_) do
    _ -> true
  end

  defmatchspecp my_matchspec(_) do
    _ -> true
  end
end
