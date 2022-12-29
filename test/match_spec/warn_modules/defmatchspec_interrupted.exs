defmodule MatchSpecTest.DefmatchspecInterrupted do
  use MatchSpec

  defmatchspec my_matchspec(:foo) do
    _ -> true
  end

  defmatchspec other_matchspec(:foo) do
    _ -> true
  end

  defmatchspec my_matchspec(:bar) do
    _ -> true
  end
end
