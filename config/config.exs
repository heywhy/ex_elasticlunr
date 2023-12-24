import Config

config :elasticlunr,
  env: config_env(),
  storage_dir: "./storage",
  max_mem_table_size: 1_000_000

if config_env() in [:dev, :test] do
  import_config("#{config_env()}.exs")
end
