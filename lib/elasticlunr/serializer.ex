defprotocol Elasticlunr.Serializer do
  @spec serialize(struct(), keyword()) :: binary() | function()
  def serialize(index, opts \\ [])
end
