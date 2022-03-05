ExUnit.start()
Faker.start()

Mox.defmock(Elasticlunr.Storage.Mock, for: Elasticlunr.Storage.Provider)
Mox.defmock(Elasticlunr.Scheduler.Mock, for: Elasticlunr.Scheduler.Behaviour)

Application.put_env(:elasticlunr, :scheduler, Elasticlunr.Scheduler.Immediate)
