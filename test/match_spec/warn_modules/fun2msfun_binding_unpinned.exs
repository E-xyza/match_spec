defmodule MatchSpecTest.Fun2msfunBindingUnpinned do
  import MatchSpec

  def warns do
    fun2msfun(fn {value} -> true end, [value])
  end
end
