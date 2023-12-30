import Config

config :elasticlunr,
  storage_dir: {:system, "STORAGE_PATH", System.tmp_dir()}

config :logger, level: :warning
