ExUnit.start()
Faker.start()

Mox.defmock(Elasticlunr.Storage.Mock, for: Elasticlunr.Storage.Provider)
