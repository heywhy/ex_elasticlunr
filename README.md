# Elasticlunr

[![Test](https://github.com/heywhy/ex_elasticlunr/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/heywhy/ex_elasticlunr/actions)

Elasticlunr is a small, full-text search library for use in the Elixir environment. It indexes JSON documents and provides a friendly search interface to retrieve documents.

## Why

The library is built for web applications that do not require the deployment complexities of popular search engines while taking advantage of the Beam capabilities.

Imagine how much is gained when the search functionality of your application resides in the same environment (Beam VM) as your business logic; search resolves faster, the number of services (Elasticsearch, Solr, and so on) to monitor reduces.

## Installation

The library can be installed by adding `elasticlunr` to your list of dependencies in mix.exs:

```elixir
def deps do
  [
    {:elasticlunr, "~> 0.5"}
  ]
end
```

Documentation can be found at [hexdocs.pm](https://hexdocs.pm/elasticlunr.). See blog post [Introduction to Elasticlunr](https://atandarash.me/blog/introduction-to-elasticlunr) and [Livebook](#livebook) for examples.

## Features

1. Query-Time Boosting, you don't need to set up boosting weight in the index building procedure, Query-Time Boosting makes it more flexible so you could try different boosting schemes
2. More Rational Scoring Mechanism, Elasticlunr.js uses a similar scoring mechanism as Elasticsearch, and also this scoring mechanism is used by Lucene
3. Field-Search, you can choose which field to index and which field to search
4. Boolean Model, you can set which field to search and the boolean model for each query token, such as "OR" and "AND"
5. Combined Boolean Model, TF/IDF Model, and the Vector Space Model make the results ranking more reliable.

## Livebook

The repository includes a livebook file that you can run. You can click the button below to run it using [livebook.dev](https://livebook.dev)!

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fheywhy%2Fex_elasticlunr%2Fblob%2Fmaster%2Fdocs.livemd)

## License

Elasticlunr is released under the MIT License - see the [LICENSE](https://github.com/heywhy/ex_elasticlunr/blob/master/LICENSE) file.
