defmodule Blackjack.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Blackjack.Registry},

      {Blackjack.Stats, []},
    ]

    opts = [strategy: :one_for_one, name: Blackjack.Supervisor]
    Supervisor.start_link(children, opts)

    Blackjack.main([])
  end
end
