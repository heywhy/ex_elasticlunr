defmodule Elasticlunr.Book do
  use Box.Index

  schema "books" do
    field(:id, :uid)
    field(:title, :text)
    field(:release_date, :date)
    field(:author, :text)
    field(:tags, {:array, :text})
    field(:views, :number)
  end
end
