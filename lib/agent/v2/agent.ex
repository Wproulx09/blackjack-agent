defmodule Blackjack.Agent.V2 do
  @moduledoc """
  Documentation for `Agent V2`
  """
  alias Blackjack.Stats, as: Record
  alias Blackjack.Agent.Utils, as: Utils
  alias Blackjack.Agent.Serializer, as: Serializer

  @version :v2
  @base_url "http://localhost:3000"
  @verbosity 1
  @session_counter :session_counter
  @number_of_sessions_to_play 10000

  @model_table :agent_model_v2
  @exploration_rate_key :exploration_rate_v2
  @model_file "agent_#{@version}_model.bin"

  @initial_exploration_rate 0.25
  @min_exploration_rate 0.02
  @exploration_decay 0.9995

  @checkpoint_interval 25


  def init_agent() do
    :ets.new(@model_table, [:named_table, :public, :set])

    {initial_stats, initial_exploration_rate} =
      case Serializer.load_model(@model_table, @model_file) do
        {:ok, metadata} ->
          exploration_rate = Map.get(metadata, :exploration_rate, @initial_exploration_rate)

          stats_from_csv = read_last_csv_line(@version)

          initial_stats = %{
            sessions: stats_from_csv.sessions,
            games: stats_from_csv.games,
            wins: stats_from_csv.wins,
            losses: stats_from_csv.losses,
            ties: stats_from_csv.ties,
            elapsed_time: stats_from_csv.elapsed_time
          }

          {initial_stats, exploration_rate}

        {:error, _} ->
          IO.puts("ℹ️  Starting fresh")
          {%{sessions: 0, games: 0, wins: 0, losses: 0, ties: 0, elapsed_time: 0}, @initial_exploration_rate}
      end

    Blackjack.Stats.start_link(@version, initial_stats)

    :persistent_term.put(@session_counter, initial_stats.sessions)
    :persistent_term.put(@exploration_rate_key, initial_exploration_rate)

    IO.puts("Start agent V2")
    session_cookie = Utils.get_session_cookie(@base_url, @verbosity)
    response_data = Utils.deal(session_cookie, @base_url, @verbosity)
    Process.delete(:trajectory)
    verify_game_state(session_cookie, response_data)
  end

  defp make_decision(session_cookie, player_hand, dealer_hand) do
    state = build_state(player_hand, dealer_hand)
    {player_score, dealer_score, has_soft_ace, ten_count} = state

    Utils.log(4, "The dealer's hand value is : #{dealer_score}", @verbosity)
    Utils.log(4, "The player's hand value is : #{player_score}", @verbosity)
    Utils.log(5, "Soft ace active? #{has_soft_ace} | Ten-values seen: #{ten_count}", @verbosity)

    action = choose_best_action(state)

    trajectory = Process.get(:trajectory, [])
    Process.put(:trajectory, [{state, action} | trajectory])

    case action do
      :hit ->
        Utils.log(4, "The agent have choose to hit", @verbosity)
        response_data = Utils.hit(session_cookie, @base_url, @verbosity)
        verify_game_state(session_cookie, response_data)
      :hold ->
        Utils.log(4, "The agent have choose to hold", @verbosity)
        response_data = Utils.hold(session_cookie, @base_url, @verbosity)
        verify_game_state(session_cookie, response_data)
    end
  end

  defp verify_game_state(session_cookie,
   %{
    "state" => game_state,
    "cash" => cash,
    "playerHand" => player_hand,
    "dealerHand" => dealer_hand
   }
  ) do
    case game_state do
      "IN_GAME" ->
        make_decision(session_cookie, player_hand, dealer_hand)
      "WON" ->
        apply_rewards(:won)
        Record.record_result(@version, "WON")
        Utils.log(3, "WON", @verbosity)
        check_cash_and_continue(session_cookie, cash)
      "LOST" ->
        apply_rewards(:lost)
        Record.record_result(@version, "LOST")
        Utils.log(3, "LOST", @verbosity)
        check_cash_and_continue(session_cookie, cash)
      "TIE" ->
        apply_rewards(:tie)
        Record.record_result(@version, "TIE")
        Utils.log(3, "TIE", @verbosity)
        check_cash_and_continue(session_cookie, cash)
      _ ->
        IO.puts("Invalid state")
    end
  end

  defp check_cash_and_continue(session_cookie, cash) do
    case cash do
      x when x <= 0 ->
        Utils.log(2, "You are now homeless ... Cash : #{cash}", @verbosity)
        Record.record_session(@version)
        check_save_checkpoint()
        Utils.end_of_session(@session_counter, @number_of_sessions_to_play, @version, @verbosity)
        Utils.restart_session(@base_url, @verbosity, fn new_session_cookie, response_data ->
          Process.delete(:trajectory)
          verify_game_state(new_session_cookie, response_data)
        end)

      x when x >= 2000 ->
        Utils.log(2, "You are so rich now !!! Cash : #{cash}", @verbosity)
        Utils.get_flag(session_cookie, @base_url, @verbosity)
        Record.record_session(@version)
        check_save_checkpoint()
        Utils.end_of_session(@session_counter, @number_of_sessions_to_play, @version, @verbosity)
        Utils.restart_session(@base_url, @verbosity, fn new_session_cookie, response_data ->
          Process.delete(:trajectory)
          verify_game_state(new_session_cookie, response_data)
        end)

      _ ->
        response_data = Utils.deal(session_cookie, @base_url, @verbosity)
        Process.delete(:trajectory)
        verify_game_state(session_cookie, response_data)
    end
  end

  defp get_model_data(state, action) do
    key = state_key(state, action)
    case :ets.lookup(@model_table, key) do
      [{_, data}] -> data
      [] -> {0, 0, 0}
    end
  end

  defp update_model(state, action, result) do
    key = state_key(state, action)
    {wins, losses, ties} = get_model_data(state, action)

    new_data = case result do
      :won -> {wins + 1, losses, ties}
      :lost -> {wins, losses + 1, ties}
      :tie -> {wins, losses, ties + 1}
    end

    :ets.insert(@model_table, {key, new_data})
  end

  defp calculate_value({wins, losses, ties}) do
    total = wins + losses + ties
    if total == 0 do
      0.0
    else
      (wins - losses) / total
    end
  end

  defp state_key({player_score, dealer_score, has_soft_ace, ten_count}, action) do
    {player_score, dealer_score, has_soft_ace, ten_count, action}
  end

  defp choose_best_action(state) do
    hit_data = get_model_data(state, :hit)
    hold_data = get_model_data(state, :hold)

    hit_value = calculate_value(hit_data)
    hold_value = calculate_value(hold_data)

    hit_total = elem(hit_data, 0) + elem(hit_data, 1) + elem(hit_data, 2)
    hold_total = elem(hold_data, 0) + elem(hold_data, 1) + elem(hold_data, 2)

    epsilon = current_exploration_rate()
    random_action = Enum.random([:hit, :hold])

    cond do
      hit_total == 0 and hold_total == 0 ->
        Utils.log(4, "No data: random action chosen : #{random_action}", @verbosity)
        random_action

      :rand.uniform() < epsilon ->
        Utils.log(
          4,
          "Exploration (ε=#{Float.round(epsilon, 3)}): #{random_action}",
          @verbosity
        )
        random_action

      true ->
        action = if hit_value >= hold_value, do: :hit, else: :hold
        Utils.log(
          4,
          "Greedy: hit=#{Float.round(hit_value, 3)} (n=#{hit_total}) vs hold=#{Float.round(hold_value, 3)} (n=#{hold_total}) -> #{action}",
          @verbosity
        )
        action
    end
  end

  defp apply_rewards(result) do
    trajectory = Process.get(:trajectory, [])

    Enum.each(trajectory, fn {state, action} ->
      update_model(state, action, result)
    end)

    decay_exploration_rate()

    Utils.log(5, "Rewarded #{length(trajectory)} actions with #{result}", @verbosity)
    Process.delete(:trajectory)
  end

  defp current_exploration_rate do
    :persistent_term.get(@exploration_rate_key, @initial_exploration_rate)
  end

  defp decay_exploration_rate do
    current = current_exploration_rate()
    new_rate = max(@min_exploration_rate, current * @exploration_decay)
    :persistent_term.put(@exploration_rate_key, new_rate)
    Utils.log(5, "Exploration rate updated to #{Float.round(new_rate, 4)}", @verbosity)
  end

  defp build_state(player_hand, dealer_hand) do
    player_score = Utils.calculate_hand_value(player_hand)
    dealer_score = Utils.calculate_hand_value(dealer_hand)
    has_soft_ace = Utils.has_soft_ace?(player_hand)
    ten_count = Utils.count_ten_value_cards(player_hand ++ dealer_hand)
    {player_score, dealer_score, has_soft_ace, ten_count}
  end

  defp check_save_checkpoint do
    session_count = :persistent_term.get(@session_counter, 0)

    if rem(session_count, @checkpoint_interval) == 0 && session_count > 0 do
      save_model_async()
    end
  end

  defp save_model_async do
    exploration_rate = current_exploration_rate()
    session_count = :persistent_term.get(@session_counter, 0)

    Task.start(fn ->
      Serializer.save_model(@model_table, @model_file, %{
        exploration_rate: exploration_rate,
        session_count: session_count,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end)
  end

  defp read_last_csv_line(version) do
    filename = "blackjack_stats_#{version}.csv"

    case File.read(filename) do
      {:ok, content} ->
        lines = String.split(content, "\n", trim: true)
        last_line = List.last(lines)

        if last_line && last_line != "games,wins,losses,ties,winrate,sessions,time" do
          case String.split(last_line, ",") do
            [games, wins, losses, ties, _winrate, sessions, time] ->
              %{
                sessions: String.to_integer(sessions),
                games: String.to_integer(games),
                wins: String.to_integer(wins),
                losses: String.to_integer(losses),
                ties: String.to_integer(ties),
                elapsed_time: String.to_integer(time)
              }
            _ ->
              %{sessions: 0, games: 0, wins: 0, losses: 0, ties: 0,  elapsed_time: 0}
          end
        else
          %{sessions: 0, games: 0, wins: 0, losses: 0, ties: 0,  elapsed_time: 0}
        end

      {:error, _} ->
        %{sessions: 0, games: 0, wins: 0, losses: 0, ties: 0}
    end
  end
  #https://chal01.hashedpotato.dev:17032/
end
