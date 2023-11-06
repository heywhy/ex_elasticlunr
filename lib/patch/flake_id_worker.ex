# FlakeId: Decentralized, k-ordered ID generation service
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: LGPL-3.0-only

defmodule FlakeIdWorker do
  @moduledoc false

  use GenServer

  defstruct node: nil, time: 0, sq: 0

  @type state :: %__MODULE__{
          node: non_neg_integer,
          time: non_neg_integer,
          sq: non_neg_integer
        }

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  @spec init([]) :: {:ok, state}
  def init([]) do
    {:ok, %__MODULE__{node: worker_id(), time: time()}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {flake, new_state} = get(time(), state)
    {:reply, flake, new_state}
  end

  @spec get :: binary
  def get, do: GenServer.call(__MODULE__, :get)

  # Matches when the calling time is the same as the state time. Incr. sq
  @spec get(non_neg_integer, state) ::
          {<<_::128>>, state} | {:error, :clock_running_backwards}
  def get(time, %__MODULE__{time: time} = state) do
    new_state = %__MODULE__{state | sq: state.sq + 1}
    {gen_flake(new_state), new_state}
  end

  # Matches when the times are different, reset sq
  def get(newtime, %__MODULE__{time: time} = state) when newtime > time do
    new_state = %__MODULE__{state | time: newtime, sq: 0}
    {gen_flake(new_state), new_state}
  end

  # Error when clock is running backwards
  def get(newtime, %__MODULE__{time: time}) when newtime < time do
    {:error, :clock_running_backwards}
  end

  @spec gen_flake(state) :: <<_::128>>
  def gen_flake(%__MODULE__{time: time, node: node, sq: seq}) do
    <<time::integer-size(64), node::integer-size(48), seq::integer-size(16)>>
  end

  def time do
    {mega_seconds, seconds, micro_seconds} = :os.timestamp()
    1_000_000_000 * mega_seconds + seconds * 1000 + :erlang.trunc(micro_seconds / 1000)
  end

  def worker_id do
    <<worker::integer-size(48)>> = :crypto.strong_rand_bytes(6)
    worker
  end
end
