defprotocol Elasticlunr.Deserializer do
  @spec deserialize(any()) :: Elasticlunr.Index.t()
  def deserialize(data)
end
