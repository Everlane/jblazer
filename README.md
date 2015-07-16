# Jblazer

Jblazer is a (work in progress) API-compatible, drop-in-replacement for Rails' [Jbuilder]. It aims to provide greater performance and extensibility by serializing JSON structures itself. In contrast, Jbuilder builds a tree of arrays/hashes/etc. before [passing that off] to MultiJson.

[Jbuilder]: https://github.com/rails/jbuilder
[passing that off]: https://github.com/rails/jbuilder/blob/c0cb50346806f7254a836b14afb5420e077c1c6f/lib/jbuilder.rb#L248-L251

## Usage

Usage with Rails is straightforward. Add `jblazer` to your Gemfile and it should automatically register itself to handle `.jblazer` templates. If you want to drop it in in place of Jbuilder then you need to instruct it to do so.

```ruby
# config/initializers/jblazer.rb or similar
Jblazer::Railtie.override_jbuilder!
```

## License

Released under the MIT license, see [LICENSE](LICENSE) for details.
