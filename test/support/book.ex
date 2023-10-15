defmodule Elasticlunr.Book do
  use Box.Index

  compaction(Compaction.Leveled, files_num_trigger: 5)

  schema "books" do
    field(:id, :uid)
    field(:title, :text)
    field(:release_date, :date)
    field(:author, :text)
    field(:tags, {:array, :text})
    field(:views, :number)
    field(:price, :number)
  end
end
