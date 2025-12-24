defmodule Blackjack.Agent.V1 do
  @moduledoc """
  Documentation for `Agent V1`
  """
  alias Blackjack.Stats, as: Record
  alias Blackjack.Agent.Utils, as: Utils

  @version :v1
  @base_url System.get_env("BLACKJACK_SERVER_URL", "http://localhost:3000")
  @verbosity 1
  @session_counter :session_counter
  @number_of_sessions_to_play 10000

  @model_table :agent_model_v1

  def init_agent() do
    Blackjack.Stats.start_link(@version)
    :persistent_term.put(@session_counter, 0)

    :ets.new(@model_table, [:named_table, :public, :set])

    IO.puts("Start agent V1")
    session_cookie = Utils.get_session_cookie(@base_url, @verbosity)
    response_data = Utils.deal(session_cookie, @base_url, @verbosity)
    Process.delete(:trajectory)
    verify_game_state(session_cookie, response_data)
  end

  defp make_decision(session_cookie, player_hand, dealer_hand) do
    player_score = Utils.calculate_hand_value(player_hand)
    dealer_score = Utils.calculate_hand_value(dealer_hand)

    Utils.log(4, "The dealer's hand value is : #{dealer_score}", @verbosity)
    Utils.log(4, "The player's hand value is : #{player_score}", @verbosity)

    action = choose_best_action(player_score, dealer_score)

    trajectory = Process.get(:trajectory, [])
    Process.put(:trajectory, [{player_score, dealer_score, action} | trajectory])

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
        Utils.end_of_session(@session_counter, @number_of_sessions_to_play, @version, @verbosity)
        Utils.restart_session(@base_url, @verbosity, fn new_session_cookie, response_data ->
          Process.delete(:trajectory)
          verify_game_state(new_session_cookie, response_data)
        end)

      x when x >= 2000 ->
        Utils.log(2, "You are so rich now !!! Cash : #{cash}", @verbosity)
        Utils.get_flag(session_cookie, @base_url, @verbosity)
        Record.record_session(@version)
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

  defp get_model_data(player_score, dealer_score, action) do
    key = {player_score, dealer_score, action}
    case :ets.lookup(@model_table, key) do
      [{_, data}] -> data
      [] -> {0, 0, 0}
    end
  end

  defp update_model(player_score, dealer_score, action, result) do
    key = {player_score, dealer_score, action}
    {wins, losses, ties} = get_model_data(player_score, dealer_score, action)

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

  defp choose_best_action(player_score, dealer_score) do
    hit_data = get_model_data(player_score, dealer_score, :hit)
    hold_data = get_model_data(player_score, dealer_score, :hold)

    hit_value = calculate_value(hit_data)
    hold_value = calculate_value(hold_data)

    hit_total = elem(hit_data, 0) +elem(hit_data, 1) + elem(hit_data, 2)
    hold_total = elem(hold_data, 0) +elem(hold_data, 1) + elem(hold_data, 2)

    if hit_total == 0 and hold_total == 0 do
      action = Enum.random([:hit, :hold])
      Utils.log(4, "No data: random action choosen : #{action}", @verbosity)
      action
    else
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

    Enum.each(trajectory, fn {player_score, dealer_score, action} ->
      update_model(player_score, dealer_score, action, result)
    end)

    Utils.log(5, "Rewarded #{length(trajectory)} actions with #{result}", @verbosity)
    Process.delete(:trajectory)
  end
  #https://chal01.hashedpotato.dev:17032/
end
