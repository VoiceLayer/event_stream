defmodule EventStream do
  @moduledoc """
  Module for encoding to and decoding from the AWS EventStream Encoding format.

  https://docs.aws.amazon.com/transcribe/latest/dg/event-stream.html
  """

  @doc """
  Encode a payload and headers to EventStream format.

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
  def encode!(payload, headers \\ []) do
    headers_binary =
      Enum.reduce(headers, <<>>, fn {key, value}, acc ->
        key = to_string(key)

        acc <> <<String.length(key)::size(8)>> <> key <> encode_header_value(value)
      end)

    header_length = byte_size(headers_binary)

    total_length = 4 + 4 + 4 + header_length + byte_size(payload) + 4
    prelude = <<total_length::size(32), header_length::size(32)>>
    prelude_crc = :erlang.crc32(prelude)

    message_without_crc = prelude <> <<prelude_crc::size(32)>> <> headers_binary <> payload
    message_crc = :erlang.crc32(message_without_crc)

    message_without_crc <> <<message_crc::size(32)>>
  end

  defp encode_header_value(value) when is_number(value) do
    <<4::size(8), value::size(32)>>
  end

  defp encode_header_value(value) when is_binary(value) do
    <<7::size(8), byte_size(value)::size(16)>> <> value
  end

  @doc """
  Encode a payload and headers to EventStream format.

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
