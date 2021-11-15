ExUnit.start()
Faker.start()

{:ok, root_path} = File.cwd()
storage_path = Path.join(root_path, "storage")

Application.put_env(:elasticlunr, :disk, dir: storage_path)
