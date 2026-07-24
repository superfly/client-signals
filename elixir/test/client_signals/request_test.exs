defmodule ClientSignals.RequestTest do
  use ExUnit.Case, async: true

  alias ClientSignals.Request

  @root Path.expand("../../..", __DIR__)

  test "classify/3 follows shared request fixtures" do
    for case <- fixture("request-classification-fixtures.json") do
      headers = case["headers"]

      assert Request.classify(
               headers["Fly-Client-Interactive"],
               headers["Fly-Client-Agent"],
               headers["Fly-Client-CI"]
             ) == %{
               operator: case["want"]["operator"],
               agent: case["want"]["agent"]
             },
             case["name"]
    end
  end

  test "tracked_api_route/4 follows shared route fixtures" do
    for case <- fixture("api-route-fixtures.json") do
      assert Request.tracked_api_route(
               case["method"],
               case["routeTemplate"],
               case["requestPath"],
               case["prefixes"]
             ) == {case["wantRoute"], case["tracked"]},
             case["name"]
    end
  end

  defp fixture(name) do
    @root
    |> Path.join("spec/#{name}")
    |> File.read!()
    |> SimpleJSON.decode!()
  end
end
