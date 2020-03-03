defmodule EventStreamTest do
  use ExUnit.Case
  doctest EventStream

  test "greets the world" do
    assert EventStream.hello() == :world
  end
end
