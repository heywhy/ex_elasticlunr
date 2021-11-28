ExUnit.start()
Faker.start()

storage_path = Path.join(__DIR__, "../storage")

Application.put_env(:elasticlunr, Elasticlunr.Storage.Disk, directory: storage_path)
