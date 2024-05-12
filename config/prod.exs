import Config

config :logger,
  level: :info,
  truncate: :infinity,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]
