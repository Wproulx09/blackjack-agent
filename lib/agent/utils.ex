defmodule Blackjack.Agent.Utils do
  @moduledoc """
  Documentation for `Agent Utils`
  """

  alias Blackjack.Stats, as: Record

  @default_bet 50

  def hold(session_cookie, base_url, verbosity) do
    execute_action("/hold", session_cookie, base_url, verbosity)
  end

  def hit(session_cookie, base_url, verbosity) do
    execute_action("/hit", session_cookie, base_url, verbosity)
  end

  def deal(session_cookie, base_url, verbosity, opts \\ []) do
    bet = Keyword.get(opts, :bet, @default_bet)
    execute_action("/deal", session_cookie, base_url, verbosity, json: %{bet: bet})
  end

  def get_flag(session_cookie, base_url, verbosity) do
    response = Req.get!(base_url <> "/flag", headers: [{"cookie", session_cookie}])

    log(1, "=" |> String.duplicate(60), verbosity)
    log(1, "FLAG OBTAINED!", verbosity)
    log(1, "=" |> String.duplicate(60), verbosity)

    case response.body do
      %{"FLAG" => flag} ->
        log(1, "FLAG: #{flag}", verbosity)

      error ->
        log(1, "Response: #{inspect(error)}", verbosity)
    end
  end

  def restart_session(base_url, verbosity, callback, opts \\ []) when is_function(callback, 2) do
    session_cookie = get_session_cookie(base_url, verbosity)
    response_data = deal(session_cookie, base_url, verbosity, opts)
    callback.(session_cookie, response_data)
  end

  def calculate_hand_value(hand) do
    {aces, other_cards} = Enum.split_with(hand, fn card -> card["rank"] == "A" end)

    base_value_without_aces =
      Enum.reduce(other_cards, 0, fn card, acc ->
        acc + card_value(card["rank"])
      end)

    Enum.reduce(aces, base_value_without_aces, fn _ace, total ->
      if total + 11 <= 21 do
        total + 11
      else
        total + 1
      end
    end)
  end

  def has_soft_ace?(hand) do
    total_with_soft = calculate_hand_value(hand)

    low_total =
      Enum.reduce(hand, 0, fn card, acc ->
        acc + low_card_value(card["rank"])
      end)

    total_with_soft > low_total
  end

  def count_ten_value_cards(cards) when is_list(cards) do
    Enum.count(cards, fn card -> ten_value_rank?(card["rank"]) end)
  end

  def card_value(rank) do
    case rank do
      "A" -> 11
      "K" -> 10
      "Q" -> 10
      "J" -> 10
      n -> String.to_integer(n)
    end
  end

  defp low_card_value("A"), do: 1
  defp low_card_value(rank), do: card_value(rank)

  defp ten_value_rank?(rank), do: rank in ["10", "J", "Q", "K"]

  def get_session_cookie(base_url, verbosity) do
    response_data = Req.get!(base_url <> "/load")
    log_inspect(5, response_data, verbosity)

    set_cookie_header = List.first(response_data.headers["set-cookie"])
    [session_cookie | _] = String.split(set_cookie_header, ";")
    session_cookie
  end

  def post(path, session_cookie, base_url, opts \\ []) do
    Req.post!(
      base_url <> path,
      Keyword.merge([headers: [{"cookie", session_cookie}]], opts)
    ).body
  end

  def log(level, message, verbosity) do
    if level <= verbosity do
      IO.puts(message)
    end
  end

  def log_inspect(level, value, verbosity) do
    if level <= verbosity do
      IO.inspect(value)
    end

    value
  end

  def end_of_session(session_counter_key, number_of_sessions_to_play, version, verbosity) do
    current = :persistent_term.get(session_counter_key)
    new_total = current + 1
    :persistent_term.put(session_counter_key, new_total)

    if rem(new_total, 25) == 0 do
      log(1, "Completed #{new_total} sessions", verbosity)
      Record.print_summary(version)
      Record.export_csv(version)
    end

    if new_total == number_of_sessions_to_play do
      System.halt(0)
    end
  end

  defp execute_action(path, session_cookie, base_url, verbosity, opts \\ []) do
    response_data = post(path, session_cookie, base_url, opts)
    log_inspect(5, response_data, verbosity)
    response_data
  end
end
