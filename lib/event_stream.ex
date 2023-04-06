defmodule EventStream do
  @type header_value_type :: pos_integer()
  @type header :: {binary(), any()} | {binary(), any(), header_value_type()}
  @type headers :: [header]

  @moduledoc """
  Module for encoding to and decoding from the AWS EventStream Encoding format.

  https://docs.aws.amazon.com/transcribe/latest/dg/event-stream.html
  """

  @doc """
  Encode a payload and headers to Event Stream format. Allows to specify
  the header value type.

  ## Examples

      iex> EventStream.encode!(~s/{"foo": "bar"}/)
      <<0, 0, 0, 30, 0, 0, 0, 0, 186, 242, 246, 138, 123, 34, 102, 111,
      111, 34, 58, 32, 34, 98, 97, 114, 34, 125, 174, 114, 88, 228>>


      iex> EventStream.encode!(~s/{"foo": "bar"}/, "content-type": "application/json")
      <<0, 0, 0, 62, 0, 0, 0, 32, 64, 93, 249, 70, 12, 99, 111, 110, 116, 101, 110,
      116, 45, 116, 121, 112, 101, 7, 0, 16, 97, 112, 112, 108, 105, 99, 97, 116,
      105, 111, 110, 47, 106, 115, 111, 110, 123, 34, 102, 111, 111, 34, 58, 32, 34,
      98, 97, 114, 34, 125, 111, 162, 191, 59>>
  """
  @spec encode!(binary(), headers()) :: binary()
  def encode!(payload, headers \\ []) do
    headers_binary =
      Enum.reduce(headers, <<>>, fn header, acc ->
        {key, value, type} = inject_header_value_type(header)
        key = to_string(key)
        acc <> <<String.length(key)::size(8)>> <> key <> encode_header_value(value, type)
      end)

    header_length = byte_size(headers_binary)

    total_length = 4 + 4 + 4 + header_length + byte_size(payload) + 4
    prelude = <<total_length::size(32), header_length::size(32)>>
    prelude_crc = :erlang.crc32(prelude)

    message_without_crc = prelude <> <<prelude_crc::size(32)>> <> headers_binary <> payload
    message_crc = :erlang.crc32(message_without_crc)

    message_without_crc <> <<message_crc::size(32)>>
  end

  defp inject_header_value_type(header = {_, _, _}), do: header

  defp inject_header_value_type({key, value}) do
    type =
      cond do
        is_number(value) -> 4
        true -> 7
      end

    {key, value, type}
  end

  # https://docs.aws.amazon.com/transcribe/latest/dg/streaming-setting-up.html#streaming-event-stream
  # Docs say that "Value string byte length: The byte length of the header value string".
  # The explicit type for strings is 7, but specifying the length is required also for these
  # other types apparently, see https://docs.aws.amazon.com/transcribe/latest/dg/streaming-http2.html
  # as an example.
  defp encode_header_value(value, type) when type in [6, 7, 8, 9] do
    <<type::integer-size(8), byte_size(value)::size(16)>> <> value
  end

  defp encode_header_value(value, _type) do
    <<4::size(8), value::size(32)>>
  end

  @doc """
  Decode a payload and headers from Event Stream format.

  ## Examples

      iex> data = <<0, 0, 0, 30, 0, 0, 0, 0, 186, 242, 246, 138, 123, 34, 102, 111,
      ...> 111, 34, 58, 32, 34, 98, 97, 114, 34, 125, 174, 114, 88, 228>>
      ...> EventStream.decode!(data)
      {:ok, [], ~s/{"foo": "bar"}/}


      iex> data = <<0, 0, 0, 62, 0, 0, 0, 32, 64, 93, 249, 70, 12, 99, 111, 110, 116, 101, 110,
      ...> 116, 45, 116, 121, 112, 101, 7, 0, 16, 97, 112, 112, 108, 105, 99, 97, 116,
      ...> 105, 111, 110, 47, 106, 115, 111, 110, 123, 34, 102, 111, 111, 34, 58, 32, 34,
      ...> 98, 97, 114, 34, 125, 111, 162, 191, 59>>
      ...> EventStream.decode!(data)
      {:ok, [{"content-type", "application/json"}], ~s/{"foo": "bar"}/}
  """
  def decode!(event_stream_message) do
    <<total_length::size(32), header_length::size(32), _prelude_crc::size(32),
      headers::binary-size(header_length), rest::binary>> = event_stream_message

    headers = decode_headers(headers, [])

    payload_length = total_length - header_length - 16
    <<payload::binary-size(payload_length), _message_crc::size(32)>> = rest

    {:ok, headers, payload}
  end

  defp decode_headers(<<>>, acc), do: Enum.reverse(acc)

  defp decode_headers(
         <<name_length::size(8), name::binary-size(name_length), 7::size(8),
           value_length::size(16), value::binary-size(value_length), rest::binary>>,
         acc
       ) do
    decode_headers(rest, [{name, value} | acc])
  end

  defp decode_headers(
         <<name_length::size(8), name::binary-size(name_length), 4::size(8), value::size(32),
           rest::binary>>,
         acc
       ) do
    decode_headers(rest, [{name, value} | acc])
  end
end
