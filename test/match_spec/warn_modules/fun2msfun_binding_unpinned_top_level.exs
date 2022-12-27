defmodule MatchSpecTest.Fun2msfunBindingUnpinnedTopLevel do
  import MatchSpec

  def warns do
    fun2msfun(fn result = tuple -> result end, [tuple])
  end
end
