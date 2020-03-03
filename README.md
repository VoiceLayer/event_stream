# EventStream

EventStream is a module for encoding to and decoding from the AWS EventStream
encoding format.

https://docs.aws.amazon.com/transcribe/latest/dg/event-stream.html

## Installation

The package can be installed by adding `event_stream` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:event_stream, "~> 0.1.0"}
  ]
end
```

Documentation can be found at [https://hexdocs.pm/event_stream](https://hexdocs.pm/event_stream).

## Example Usage:

### Encoding:

```
data = EventStream.encode!(~s/{"foo": "bar"}/)
<<0, 0, 0, 30, 0, 0, 0, 0, 186, 242, 246, 138, 123, 34, 102, 111,
  111, 34, 58, 32, 34, 98, 97, 114, 34, 125, 174, 114, 88, 228>>
```

### Decoding:

```
data = <<0, 0, 0, 30, 0, 0, 0, 0, 186, 242, 246, 138, 123, 34, 102, 111,
  111, 34, 58, 32, 34, 98, 97, 114, 34, 125, 174, 114, 88, 228>>
EventStream.decode!(data)
{:ok, [], ~s/{"foo": "bar"}/}
```
