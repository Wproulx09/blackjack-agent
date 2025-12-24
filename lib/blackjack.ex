defmodule Blackjack do
  @moduledoc """
  Documentation for `Blackjack`.
  """
  alias Blackjack.Agent.VO, as: AgentV0
  alias Blackjack.Agent.V1, as: AgentV1
  alias Blackjack.Agent.V2, as: AgentV2
  alias Blackjack.Agent.V3, as: AgentV3

  def main(_args) do
    IO.puts("Welcome to Blackjack !")
    choose_version()
  end

  defp choose_version do
    version = IO.gets("Select the version of the blackjack agent you want to play with : ")

    version = version
    |> String.trim()
    |> String.to_integer()

    case version do
      0 -> AgentV0.init_agent()
      1 -> AgentV1.init_agent()
      2 -> AgentV2.init_agent()
      3 -> AgentV3.init_agent()
      _ -> IO.puts("Please select a valid version.")
    end
  end
end
