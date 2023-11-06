defmodule Elasticlunr.Telemeter do
  @moduledoc """
  Documentation for `Elasticlunr.Telemeter`. Api based on https://keathley.io/blog/telemetry-conventions.html
  """

  @otp_app :elasticlunr

  @spec start(atom(), map(), map() | nil) :: pos_integer() | no_return()
  def start(name, meta, measurements \\ %{}) do
    time = System.monotonic_time()
    measures = Map.put(measurements, :system_time, time)
    :ok = :telemetry.execute([@otp_app, name, :start], measures, meta)
    time
  end

  @spec stop(atom(), pos_integer(), map(), map() | nil) :: :ok
  def stop(name, start_time, meta, measurements \\ %{}) do
    end_time = System.monotonic_time()
    measurements = Map.merge(measurements, %{duration: end_time - start_time})

    :telemetry.execute(
      [@otp_app, name, :stop],
      measurements,
      meta
    )
  end

  @spec event(atom(), map(), map()) :: :ok
  def event(name, metrics, meta) do
    :telemetry.execute([@otp_app, name], metrics, meta)
  end

  @spec track(atom(), map(), function()) :: :telemetry.span_result()
  def track(name, metadata, callback) do
    :telemetry.span([@otp_app, name], metadata, fn ->
      case callback.() do
        {result, extra} -> {result, Map.merge(metadata, extra)}
        result -> {result, metadata}
      end
    end)
  end
end
