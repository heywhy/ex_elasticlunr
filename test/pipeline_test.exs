defmodule Elasticlunr.PipelineTest do
  use ExUnit.Case

  alias Elasticlunr.{Pipeline, Tokenizer}
  alias Elasticlunr.Pipeline.{Trimmer}

  describe "creating pipeline" do
    test "adds a runner to the queue" do
      assert pipeline = Pipeline.new([])
      assert %Pipeline{callback: []} = pipeline
      assert %Pipeline{callback: [Trimmer]} = Pipeline.add(pipeline, Trimmer)
    end

    test "ignores duplicate runner in the queue" do
      pipeline = Pipeline.new([])
      assert %Pipeline{callback: []} = pipeline
      assert %Pipeline{callback: [Trimmer]} = Pipeline.add(pipeline, Trimmer)
      assert %Pipeline{callback: [Trimmer]} = Pipeline.add(pipeline, Trimmer)
    end
  end

  describe "running pipeline" do
    test "executes runners in the queue" do
      pipeline = Pipeline.new(Pipeline.default_runners())
      tokens = Tokenizer.tokenize("hello world")

      assert ^tokens = Pipeline.run(pipeline, tokens)
    end
  end
end
