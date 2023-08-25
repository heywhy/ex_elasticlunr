import Config

config :elasticlunr,
  storage_dir: "./storage",
  max_mem_table_size: 1_000_000

if config_env() == :test do
  import_config("test.exs")
end
