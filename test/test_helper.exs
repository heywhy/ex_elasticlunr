ExUnit.start()
Faker.start()

Mox.defmock(Elasticlunr.Storage.Mock, for: Elasticlunr.Storage.Provider)
Application.put_env(:elasticlunr, :scheduler, Elasticlunr.Scheduler.Immediate)
