import Config

config :elasticlunr,
  env: config_env(),
  storage_dir: "./storage",
  max_mem_table_size: 1_000_000

config :logger, :default_formatter, metadata: [:application, :index, :mfa]

import_config("#{config_env()}.exs")
