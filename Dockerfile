FROM elixir:1.16.2-slim

RUN apt-get update -y && apt-get install -y build-essential && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV=dev

COPY mix.exs ./
RUN mix deps.get && mix deps.compile

COPY . .

CMD ["mix", "phx.server"]
