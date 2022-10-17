defmodule PyCellTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  import Kino.Test

  doctest PyCell

  setup :configure_livebook_bridge

  test "supplies its hardcoded source" do
    default_source = """
    def add(a, b):
      return a + b
    """

    {_kino, source} = start_smart_cell!(PyCell, %{})

    escaped_default_source = Jason.encode!(default_source)

    assert source == "PyCell.open_port(\"add\", #{escaped_default_source})"
  end

  test "gives instructions to the user" do
    {_kino, source} = start_smart_cell!(PyCell, %{})

    run_source = fn ->
      {:ok, _} = Code.eval_string(source)
    end

    assert capture_io(run_source) == """
           Run the \"add\" function by running:
           require PyCell
           PyCell.run(\"add\", <args>)
           """
  end

  test "supplies its custom source" do
    custom_source = """
    def sub(a, b):
      return a - b
    """

    {_kino, source} =
      start_smart_cell!(PyCell, %{"default_source" => custom_source, "function_name" => "sub"})

    escaped_custom_source = Jason.encode!(custom_source)

    assert source == "PyCell.open_port(\"sub\", #{escaped_custom_source})"
  end

  test "running a PyCell works" do
    default_source = """
    def add(a, b):
      return a + b
    """

    {_kino, source} = start_smart_cell!(PyCell, %{"default_source" => default_source})

    assert {:ok, _} = Code.eval_string(source)

    assert {3, _} =
             Code.eval_string("""
             require PyCell
             PyCell.run("add", [1,2])
             """)
  end

  test "running a PyCell with bad args returns an `:error`" do
    default_source = """
    def add(a, b):
      return a + b
    """

    {_kino, source} = start_smart_cell!(PyCell, %{"default_source" => default_source})

    assert {:ok, _} = Code.eval_string(source)

    assert {:error, _} =
             Code.eval_string("""
             require PyCell
             PyCell.run("add", [1,2,3])
             """)
  end

  test "long-running tasks are interrupted" do
    default_source = """
    import time
    def add(a, b):
      time.sleep(1000)
      return a + b
    """

    {_kino, source} = start_smart_cell!(PyCell, %{"default_source" => default_source})

    assert {:ok, _} = Code.eval_string(source)

    assert {:timeout, _} =
             Code.eval_string("""
             require PyCell
             PyCell.run("add", [1,2], 200)
             """)
  end
end
