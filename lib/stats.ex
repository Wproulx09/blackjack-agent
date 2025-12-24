defmodule Blackjack.Stats do
  use Agent

  def start_link(version,  initial_data \\ %{}) do
    Agent.start_link(fn ->
                        now = System.monotonic_time()
                        elapsed_seconds = Map.get(initial_data, :elapsed_time, 0)
                        adjusted_start_time = now - System.convert_time_unit(elapsed_seconds, :second, :native)

                        %{
                          sessions: Map.get(initial_data, :sessions, 0),
                          games: Map.get(initial_data, :games, 0),
                          wins: Map.get(initial_data, :wins, 0),
                          losses: Map.get(initial_data, :losses, 0),
                          ties: Map.get(initial_data, :ties, 0),
                          start_time:  adjusted_start_time,
                          history: [],
                          last_exported_index: 0
                        }
    end, name: via(version))
  end

  defp via(version), do: {:via, Registry, {Blackjack.Registry, version}}

  def record_result(version, result) do
    Agent.update(via(version), fn stats ->
      stats
      |> increment_game()
      |> increment_result(result)
      |> add_history_snapshot()
    end)
  end

  def record_session(version) do
    Agent.update(via(version), fn stats ->
      %{stats | sessions: stats.sessions + 1}
    end)
  end

  def current_stats(version) do
    Agent.get(via(version), & &1)
  end

  defp increment_game(stats), do: %{stats | games: stats.games + 1}

  defp increment_result(stats, "WON"),  do: %{stats | wins: stats.wins + 1}
  defp increment_result(stats, "LOST"), do: %{stats | losses: stats.losses + 1}
  defp increment_result(stats, "TIE"),  do: %{stats | ties: stats.ties + 1}
  defp increment_result(stats, _),      do: stats

  defp add_history_snapshot(stats) do
    now = System.monotonic_time()
    elapsed_sec = System.convert_time_unit(now - stats.start_time, :native, :second)

    snapshot = %{
      sessions: stats.sessions,
      games: stats.games,
      wins: stats.wins,
      losses: stats.losses,
      ties: stats.ties,
      winrate: winrate(stats),
      time: elapsed_sec
    }

    %{stats | history: [snapshot | stats.history]}
  end

  def winrate(stats) do
    if stats.games == 0 do
      0.0
    else
      stats.wins / stats.games
    end
  end

  def print_summary(version) do
    stats = current_stats(version)
    IO.puts("""
    === SUMMARY for #{version} ===
    Sessions: #{stats.sessions}
    Games: #{stats.games}
    Wins: #{stats.wins}
    Losses: #{stats.losses}
    Ties: #{stats.ties}
    Winrate: #{Float.round(stats.wins / stats.games * 100, 2)}%
    =============================
    """)
  end

  def export_csv(version) do
    Agent.get_and_update(via(version), fn stats ->
      filename = "blackjack_stats_#{version}.csv"

      unless File.exists?(filename) do
        File.write!(filename, "games,wins,losses,ties,winrate,sessions,time\n")
      end

      history_reversed = Enum.reverse(stats.history)
      new_entries = Enum.drop(history_reversed, stats.last_exported_index)

      Enum.each(new_entries, fn s ->
        line = "#{s.games},#{s.wins},#{s.losses},#{s.ties},#{Float.round(s.winrate, 4)},#{s.sessions},#{s.time}\n"
        File.write!(filename, line, [:append])
      end)

      new_stats = %{stats | last_exported_index: length(history_reversed)}

      {:ok, new_stats}
    end)
  end

end
