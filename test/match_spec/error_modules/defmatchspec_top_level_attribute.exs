defmodule MatchSpecTest.DefmatchspecTopLevelAttribute do
  use MatchSpec

  @attribute {:key, :value}

  defmatchspec my_matchspec(_) do
    @attribute -> true
  end
end
