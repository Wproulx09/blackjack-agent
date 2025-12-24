defmodule Blackjack.Agent.VO do
  @moduledoc """
  Documentation for `Agent V0`
  """

  alias Blackjack.Stats, as: Record
  alias Blackjack.Agent.Utils, as: Utils

  @version :v0
  @base_url System.get_env("BLACKJACK_SERVER_URL", "http://localhost:3000")
  @verbosity 1
  @session_counter :session_counter
  @number_of_sessions_to_play 10000

  def init_agent() do
    Blackjack.Stats.start_link(@version)
    :persistent_term.put(@session_counter, 0)

    IO.puts("Start agent V0")
    session_cookie = Utils.get_session_cookie(@base_url, @verbosity)
    response_data = Utils.deal(session_cookie, @base_url, @verbosity)
    verify_game_state(session_cookie, response_data)
  end

  defp make_decision(session_cookie, player_hand, dealer_hand) do
    random_choice = :rand.uniform(2)
    dealer_value = Utils.calculate_hand_value(dealer_hand)
    player_value = Utils.calculate_hand_value(player_hand)

    Utils.log(4, "The dealer's hand value is : #{dealer_value}", @verbosity)
    Utils.log(4, "The player's hand value is : #{player_value}", @verbosity)

    case random_choice do
      1 ->
        Utils.log(4, "The agent have choose to hit", @verbosity)
        response_data = Utils.hit(session_cookie, @base_url, @verbosity)
        verify_game_state(session_cookie, response_data)

      2 ->
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
        Record.record_result(@version, "WON")
        Utils.log(3, "WON", @verbosity)
        check_cash_and_continue(session_cookie, cash)
      "LOST" ->
        Record.record_result(@version, "LOST")
        Utils.log(3, "LOST", @verbosity)
        check_cash_and_continue(session_cookie, cash)
      "TIE" ->
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
        Utils.restart_session(@base_url, @verbosity, &verify_game_state/2)

      x when x >= 2000 ->
        Utils.log(2, "You are so rich now !!! Cash : #{cash}", @verbosity)
        Record.record_session(@version)
        Utils.end_of_session(@session_counter, @number_of_sessions_to_play, @version, @verbosity)
        Utils.restart_session(@base_url, @verbosity, &verify_game_state/2)

      _ ->
        response_data = Utils.deal(session_cookie, @base_url, @verbosity)
        verify_game_state(session_cookie, response_data)
    end
  end

  #https://chal01.hashedpotato.dev:17032/
end
