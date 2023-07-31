defmodule EventStream do
  @type(
    header_value_type :: :boolean,
    :byte,
    :short,
    :integer,
    :long,
    :byte_array,
    :string,
    :timestamp,
    :uuid
  )
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
    headers_binary = encode_headers!(headers)
    header_length = byte_size(headers_binary)

    total_length = 4 + 4 + 4 + header_length + byte_size(payload) + 4
    prelude = <<total_length::size(32), header_length::size(32)>>
    prelude_crc = :erlang.crc32(prelude)

    message_without_crc = prelude <> <<prelude_crc::size(32)>> <> headers_binary <> payload
    message_crc = :erlang.crc32(message_without_crc)

    message_without_crc <> <<message_crc::size(32)>>
  end

  def encode_headers!(headers) do
    Enum.reduce(headers, <<>>, fn header, acc ->
      {key, value, type} = inject_header_value_type(header)
      key = to_string(key)
      acc <> <<String.length(key)::size(8)>> <> key <> encode_header_value(value, type)
    end)
  end

  defp inject_header_value_type(header = {_, _, _}), do: header
  defp inject_header_value_type({key, value}), do: {key, value, :string}

  defp encode_header_value(true, :boolean) do
    <<0::integer-size(8)>>
  end

  defp encode_header_value(false, :boolean) do
    <<1::integer-size(8)>>
  end

  defp encode_header_value(value, :byte) do
    <<2::integer-size(8), value::big-signed-integer-size(8)>>
  end

  defp encode_header_value(value, :short) do
    <<3::integer-size(8), value::big-signed-integer-size(16)>>
  end

  defp encode_header_value(value, :integer) do
    <<4::integer-size(8), value::big-signed-integer-size(32)>>
  end

  defp encode_header_value(value, :long) do
    <<5::integer-size(8), value::big-signed-integer-size(64)>>
  end

  defp encode_header_value(value, :byte_array) do
    <<6::integer-size(8), byte_size(value)::big-signed-size(16), value::binary>>
  end

  defp encode_header_value(value, :string) do
    <<7::integer-size(8), byte_size(value)::size(16), value::binary>>
  end

  defp encode_header_value({{year, month, day}, {hour, minute, second}}, :timestamp) do
    Date.new!(year, month, day)
    |> DateTime.new!(Time.new!(hour, minute, second))
    |> encode_header_value(:timestamp)
  end

  defp encode_header_value(value, :timestamp) do
    value = DateTime.to_unix(value, :millisecond)
    <<8::integer-size(8), value::big-signed-integer-size(64)>>
  end

  defp encode_header_value(value, :uuid) do
    <<9::integer-size(8), value::size(16)>>
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
      {:ok, [{"content-type", "application/json", :string}], ~s/{"foo": "bar"}/}
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

  defp decode_headers(<<name_length::size(8), name::binary-size(name_length), rest::binary>>, acc) do
    {value, type, rest} = decode_header_value(rest)
    decode_headers(rest, [{name, value, type} | acc])
  end

  defp decode_header_value(<<0::size(8), rest::binary>>) do
    {true, :boolean, rest}
  end

  defp decode_header_value(<<1::size(8), rest::binary>>) do
    {false, :boolean, rest}
  end

  defp decode_header_value(<<2::size(8), value::big-signed-integer-size(8), rest::binary>>) do
    {value, :byte, rest}
  end

  defp decode_header_value(<<3::size(8), value::big-signed-integer-size(16), rest::binary>>) do
    {value, :short, rest}
  end

  defp decode_header_value(<<4::size(8), value::big-signed-integer-size(32), rest::binary>>) do
    {value, :integer, rest}
  end

  defp decode_header_value(<<5::size(8), value::big-signed-integer-size(64), rest::binary>>) do
    {value, :long, rest}
  end

  defp decode_header_value(
         <<6::size(8), value_length::size(16), value::binary-size(value_length), rest::binary>>
       ) do
    {value, :byte_array, rest}
  end

  defp decode_header_value(
         <<7::size(8), value_length::size(16), value::binary-size(value_length), rest::binary>>
       ) do
    {value, :string, rest}
  end

  defp decode_header_value(<<8::size(8), value::big-signed-integer-size(64), rest::binary>>) do
    {DateTime.from_unix!(value, :millisecond), :timestamp, rest}
  end

  defp decode_header_value(<<9::size(8), value::binary-size(16), rest::binary>>) do
    {value, :uuid, rest}
  end
end
