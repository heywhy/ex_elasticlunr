defmodule Elasticlunr.PipelineTest do
  use ExUnit.Case

  alias Elasticlunr.{Pipeline, Tokenizer}
  alias Elasticlunr.Pipeline.{Stemmer, StopWordFilter, Trimmer}

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

  describe "updating pipeline" do
    test "removes runner from queue" do
      pipeline = Pipeline.new([Stemmer, Trimmer])

      assert %Pipeline{callback: [Stemmer, Trimmer]} = pipeline
      assert %Pipeline{callback: [Stemmer]} = Pipeline.remove(pipeline, Trimmer)
    end

    test "inserts runner at position" do
      pipeline = Pipeline.new([Stemmer, Trimmer])

      assert %Pipeline{callback: [Stemmer, Trimmer]} = pipeline

      assert pipeline = Pipeline.insert_before(pipeline, StopWordFilter, Trimmer)
      assert %Pipeline{callback: [Stemmer, StopWordFilter, Trimmer]} = pipeline
      assert pipeline = Pipeline.remove(pipeline, Stemmer)
      assert %Pipeline{callback: [StopWordFilter, Trimmer]} = pipeline

      assert %Pipeline{callback: [StopWordFilter, Stemmer, Trimmer]} =
               Pipeline.insert_after(pipeline, Stemmer, StopWordFilter)
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
