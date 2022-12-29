defmodule MatchSpecTest.DefmatchspecpInterrupted do
  use MatchSpec

  defmatchspecp my_matchspec(:foo) do
    _ -> true
  end

  defmatchspecp other_matchspec(:foo) do
    _ -> true
  end

  defmatchspecp my_matchspec(:bar) do
    _ -> true
  end
end
