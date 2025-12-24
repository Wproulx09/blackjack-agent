FROM elixir:1.19-alpine AS build

WORKDIR /app

ENV MIX_ENV=prod
ENV BLACKJACK_SERVER_URL=http://host.docker.internal:3000

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY . .
RUN mix compile

FROM elixir:1.19-alpine AS runtime

WORKDIR /app

ENV MIX_ENV=prod
ENV BLACKJACK_SERVER_URL=http://host.docker.internal:3000

COPY --from=build /app /app

CMD ["mix", "run", "--no-halt"]