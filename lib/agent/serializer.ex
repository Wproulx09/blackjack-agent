defmodule Blackjack.Agent.Serializer do
  @moduledoc """
  Module de sérialisation pour sauvegarder et charger les modèles d'agents
  """

  def save_model(table, filename, metadata \\ %{}) do
    all_data = :ets.tab2list(table)

    binary = :erlang.term_to_binary({all_data, metadata}, [:compressed])

    File.write(filename, binary)
  end

  def load_model(table, filename) do
    case File.read(filename) do
      {:ok, binary} ->
        {all_data, metadata} = :erlang.binary_to_term(binary)

        Enum.each(all_data, fn item ->
          :ets.insert(table, item)
        end)

        {:ok, metadata}

      {:error, reason} -> {:error, reason}
    end
  end

  def export_summary(table, filename) do
    all_data = :ets.tab2list(table)

    summary =
      all_data
      |> Enum.map(fn {{player_score, dealer_score, has_soft_ace, ten_count, action}, {wins, losses, ties}} ->
        total = wins + losses + ties
        value = if total > 0, do: (wins - losses) / total, else: 0.0

        %{
          player_score: player_score,
          dealer_score: dealer_score,
          has_soft_ace: has_soft_ace,
          ten_count: ten_count,
          action: action,
          wins: wins,
          losses: losses,
          ties: ties,
          total: total,
          value: Float.round(value, 4)
        }
      end)
      |> Enum.sort_by(&{&1.player_score, &1.dealer_score, &1.action})

    csv_content = [
      "player_score,dealer_score,has_soft_ace,ten_count,action,wins,losses,ties,total,value\n"
      | Enum.map(summary, fn s ->
        "#{s.player_score},#{s.dealer_score},#{s.has_soft_ace},#{s.ten_count},#{s.action},#{s.wins},#{s.losses},#{s.ties},#{s.total},#{s.value}\n"
      end)
    ]

    File.write(filename, csv_content)
  end

  def get_model_stats(table) do
    all_data = :ets.tab2list(table)

    total_states = length(all_data)
    total_samples =
      Enum.reduce(all_data, 0, fn {_key, {wins, losses, ties}}, acc ->
        acc + wins + losses + ties
      end)

    %{
      total_states: total_states,
      total_samples: total_samples,
      avg_samples_per_state: if(total_states > 0, do: total_samples / total_states, else: 0)
    }
  end
end