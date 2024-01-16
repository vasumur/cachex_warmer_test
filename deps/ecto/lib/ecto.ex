defmodule Ecto do
  @moduledoc ~S"""
  Ecto is split into 4 main components:

    * `Ecto.Repo` - repositories are wrappers around the data store.
      Via the repository, we can create, update, destroy and query
      existing entries. A repository needs an adapter and credentials
      to communicate to the database

    * `Ecto.Schema` - schemas are used to map external data into Elixir
      structs. We often use them to map database tables to Elixir data but
      they have many other use cases

    * `Ecto.Query` - written in Elixir syntax, queries are used to retrieve
      information from a given repository. Ecto queries are secure and composable

    * `Ecto.Changeset` - changesets provide a way to track and validate changes
      before they are applied to the data

  In summary:

    * `Ecto.Repo` - **where** the data is
    * `Ecto.Schema` - **what** the data is
    * `Ecto.Query` - **how to read** the data
    * `Ecto.Changeset` - **how to change** the data

  Besides the four components above, most developers use Ecto to interact
  with SQL databases, such as PostgreSQL and MySQL via the
  [`ecto_sql`](https://hexdocs.pm/ecto_sql) project. `ecto_sql` provides many
  conveniences for working with SQL databases as well as the ability to version
  how your database changes through time via
  [database migrations](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.html#module-migrations).

  If you want to quickly check a sample application using Ecto, please check
  the [getting started guide](https://hexdocs.pm/ecto/getting-started.html) and
  the accompanying sample application. [Ecto's README](https://github.com/elixir-ecto/ecto)
  also links to other resources.

  In the following sections, we will provide an overview of those components and
  how they interact with each other. Feel free to access their respective module
  documentation for more specific examples, options and configuration.

  ## Repositories

  `Ecto.Repo` is a wrapper around the database. We can define a
  repository as follows:

      defmodule Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Postgres
      end

  Where the configuration for the Repo must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, Repo,
        database: "ecto_simple",
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        # OR use a URL to connect instead
        url: "postgres://postgres:postgres@localhost/ecto_simple"

  Each repository in Ecto defines a `start_link/0` function that needs to be invoked
  before using the repository. In general, this function is not called directly,
  but is used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup` to `mix new`)
  you will have a `lib/my_app/application.ex` file containing the application start
  callback that defines and starts your supervisor.  You just need to edit the `start/2`
  function to start the repo as a supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          MyApp.Repo,
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## Schema

  Schemas allow developers to define the shape of their data.
  Let's see an example:

      defmodule Weather do
        use Ecto.Schema

        # weather is the DB table
        schema "weather" do
          field :city,    :string
          field :temp_lo, :integer
          field :temp_hi, :integer
          field :prcp,    :float, default: 0.0
        end
      end

  By defining a schema, Ecto automatically defines a struct with
  the schema fields:

      iex> weather = %Weather{temp_lo: 30}
      iex> weather.temp_lo
      30

  The schema also allows us to interact with a repository:

      iex> weather = %Weather{temp_lo: 0, temp_hi: 23}
      iex> Repo.insert!(weather)
      %Weather{...}

  After persisting `weather` to the database, it will return a new copy of
  `%Weather{}` with the primary key (the `id`) set. We can use this value
  to read a struct back from the repository:

      # Get the struct back
      iex> weather = Repo.get Weather, 1
      %Weather{id: 1, ...}

      # Delete it
      iex> Repo.delete!(weather)
      %Weather{...}

  > NOTE: by using `Ecto.Schema`, an `:id` field with type `:id` (:id means :integer) is
  > generated by default, which is the primary key of the schema. If you want
  > to use a different primary key, you can declare custom `@primary_key`
  > before the `schema/2` call. Consult the `Ecto.Schema` documentation
  > for more information.

  Notice how the storage (repository) and the data are decoupled. This provides
  two main benefits:

    * By having structs as data, we guarantee they are light-weight,
      serializable structures. In many languages, the data is often represented
      by large, complex objects, with entwined state transactions, which makes
      serialization, maintenance and understanding hard;

    * You do not need to define schemas in order to interact with repositories,
      operations like `all`, `insert_all` and so on allow developers to directly
      access and modify the data, keeping the database at your fingertips when
      necessary;

  ## Changesets

  Although in the example above we have directly inserted and deleted the
  struct in the repository, operations on top of schemas are done through
  changesets so Ecto can efficiently track changes.

  Changesets allow developers to filter, cast, and validate changes before
  we apply them to the data. Imagine the given schema:

      defmodule User do
        use Ecto.Schema

        import Ecto.Changeset

        schema "users" do
          field :name
          field :email
          field :age, :integer
        end

        def changeset(user, params \\ %{}) do
          user
          |> cast(params, [:name, :email, :age])
          |> validate_required([:name, :email])
          |> validate_format(:email, ~r/@/)
          |> validate_inclusion(:age, 18..100)
        end
      end

  The `changeset/2` function first invokes `Ecto.Changeset.cast/4` with
  the struct, the parameters and a list of allowed fields; this returns a changeset.
  The parameters is a map with binary keys and values that will be cast based
  on the type defined by the schema.

  Any parameter that was not explicitly listed in the fields list will be ignored.

  After casting, the changeset is given to many `Ecto.Changeset.validate_*`
  functions that validate only the **changed fields**. In other words:
  if a field was not given as a parameter, it won't be validated at all.
  For example, if the params map contain only the "name" and "email" keys,
  the "age" validation won't run.

  Once a changeset is built, it can be given to functions like `insert` and
  `update` in the repository that will return an `:ok` or `:error` tuple:

      case Repo.update(changeset) do
        {:ok, user} ->
          # user updated
        {:error, changeset} ->
          # an error occurred
      end

  The benefit of having explicit changesets is that we can easily provide
  different changesets for different use cases. For example, one
  could easily provide specific changesets for registering and updating
  users:

      def registration_changeset(user, params) do
        # Changeset on create
      end

      def update_changeset(user, params) do
        # Changeset on update
      end

  Changesets are also capable of transforming database constraints,
  like unique indexes and foreign key checks, into errors. Allowing
  developers to keep their database consistent while still providing
  proper feedback to end users. Check `Ecto.Changeset.unique_constraint/3`
  for some examples as well as the other `_constraint` functions.

  ## Query

  Last but not least, Ecto allows you to write queries in Elixir and send
  them to the repository, which translates them to the underlying database.
  Let's see an example:

      import Ecto.Query, only: [from: 2]

      query = from u in User,
                where: u.age > 18 or is_nil(u.email),
                select: u

      # Returns %User{} structs matching the query
      Repo.all(query)

  In the example above we relied on our schema but queries can also be
  made directly against a table by giving the table name as a string. In
  such cases, the data to be fetched must be explicitly outlined:

      query = from u in "users",
                where: u.age > 18 or is_nil(u.email),
                select: %{name: u.name, age: u.age}

      # Returns maps as defined in select
      Repo.all(query)

  Queries are defined and extended with the `from` macro. The supported
  keywords are:

    * `:distinct`
    * `:where`
    * `:order_by`
    * `:offset`
    * `:limit`
    * `:lock`
    * `:group_by`
    * `:having`
    * `:join`
    * `:select`
    * `:preload`

  Examples and detailed documentation for each of those are available
  in the `Ecto.Query` module. Functions supported in queries are listed
  in `Ecto.Query.API`.

  When writing a query, you are inside Ecto's query syntax. In order to
  access params values or invoke Elixir functions, you need to use the `^`
  operator, which is overloaded by Ecto:

      def min_age(min) do
        from u in User, where: u.age > ^min
      end

  Besides `Repo.all/1` which returns all entries, repositories also
  provide `Repo.one/1` which returns one entry or nil, `Repo.one!/1`
  which returns one entry or raises, `Repo.get/2` which fetches
  entries for a particular ID and more.

  Finally, if you need an escape hatch, Ecto provides fragments
  (see `Ecto.Query.API.fragment/1`) to inject SQL (and non-SQL)
  fragments into queries. Also, most adapters provide direct
  APIs for queries, like `Ecto.Adapters.SQL.query/4`, allowing
  developers to completely bypass Ecto queries.

  ## Other topics

  ### Associations

  Ecto supports defining associations on schemas:

      defmodule Post do
        use Ecto.Schema

        schema "posts" do
          has_many :comments, Comment
        end
      end

      defmodule Comment do
        use Ecto.Schema

        schema "comments" do
          field :title, :string
          belongs_to :post, Post
        end
      end

  When an association is defined, Ecto also defines a field in the schema
  with the association name. By default, associations are not loaded into
  this field:

      iex> post = Repo.get(Post, 42)
      iex> post.comments
      #Ecto.Association.NotLoaded<...>

  However, developers can use the preload functionality in queries to
  automatically pre-populate the field:

      Repo.all from p in Post, preload: [:comments]

  Preloading can also be done with a pre-defined join value:

      Repo.all from p in Post,
                join: c in assoc(p, :comments),
                where: c.votes > p.votes,
                preload: [comments: c]

  Finally, for the simple cases, preloading can also be done after
  a collection was fetched:

      posts = Repo.all(Post) |> Repo.preload(:comments)

  The `Ecto` module also provides conveniences for working
  with associations. For example, `Ecto.assoc/3` returns a query
  with all associated data to a given struct:

      import Ecto

      # Get all comments for the given post
      Repo.all assoc(post, :comments)

      # Or build a query on top of the associated comments
      query = from c in assoc(post, :comments), where: not is_nil(c.title)
      Repo.all(query)

  Another function in `Ecto` is `build_assoc/3`, which allows
  someone to build an associated struct with the proper fields:

      Repo.transaction fn ->
        post = Repo.insert!(%Post{title: "Hello", body: "world"})

        # Build a comment from post
        comment = Ecto.build_assoc(post, :comments, body: "Excellent!")

        Repo.insert!(comment)
      end

  In the example above, `Ecto.build_assoc/3` is equivalent to:

      %Comment{post_id: post.id, body: "Excellent!"}

  You can find more information about defining associations and each
  respective association module in `Ecto.Schema` docs.

  > NOTE: Ecto does not lazy load associations. While lazily loading
  > associations may sound convenient at first, in the long run it
  > becomes a source of confusion and performance issues.

  ### Embeds

  Ecto also supports embeds. While associations keep parent and child
  entries in different tables, embeds stores the child along side the
  parent.

  Databases like MongoDB have native support for embeds. Databases
  like PostgreSQL uses a mixture of JSONB (`embeds_one/3`) and ARRAY
  columns to provide this functionality.

  Check `Ecto.Schema.embeds_one/3` and `Ecto.Schema.embeds_many/3`
  for more information.

  ### Mix tasks and generators

  Ecto provides many tasks to help your workflow as well as code generators.
  You can find all available tasks by typing `mix help` inside a project
  with Ecto listed as a dependency.

  Ecto generators will automatically open the generated files if you have
  `ECTO_EDITOR` set in your environment variable.

  #### Repo resolution

  Ecto requires developers to specify the key `:ecto_repos` in their
  application configuration before using tasks like `ecto.create` and
  `ecto.migrate`. For example:

      config :my_app, :ecto_repos, [MyApp.Repo]

      config :my_app, MyApp.Repo,
        database: "ecto_simple",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

  """

  @doc """
  Returns the schema primary keys as a keyword list.
  """
  @spec primary_key(Ecto.Schema.t()) :: Keyword.t()
  def primary_key(%{__struct__: schema} = struct) do
    Enum.map(schema.__schema__(:primary_key), fn field ->
      {field, Map.fetch!(struct, field)}
    end)
  end

  @doc """
  Returns the schema primary keys as a keyword list.

  Raises `Ecto.NoPrimaryKeyFieldError` if the schema has no
  primary key field.
  """
  @spec primary_key!(Ecto.Schema.t()) :: Keyword.t()
  def primary_key!(%{__struct__: schema} = struct) do
    case primary_key(struct) do
      [] -> raise Ecto.NoPrimaryKeyFieldError, schema: schema
      pk -> pk
    end
  end

  @doc """
  Builds a struct from the given `assoc` in `struct`.

  ## Examples

  If the relationship is a `has_one` or `has_many` and
  the primary key is set in the parent struct, the key will
  automatically be set in the built association:

      iex> post = Repo.get(Post, 13)
      %Post{id: 13}
      iex> build_assoc(post, :comments)
      %Comment{id: nil, post_id: 13}

  Note though it doesn't happen with `belongs_to` cases, as the
  key is often the primary key and such is usually generated
  dynamically:

      iex> comment = Repo.get(Comment, 13)
      %Comment{id: 13, post_id: 25}
      iex> build_assoc(comment, :post)
      %Post{id: nil}

  You can also pass the attributes, which can be a map or
  a keyword list, to set the struct's fields except the
  association key.

      iex> build_assoc(post, :comments, text: "cool")
      %Comment{id: nil, post_id: 13, text: "cool"}

      iex> build_assoc(post, :comments, %{text: "cool"})
      %Comment{id: nil, post_id: 13, text: "cool"}

      iex> build_assoc(post, :comments, post_id: 1)
      %Comment{id: nil, post_id: 13}

  The given attributes are expected to be structured data.
  If you want to build an association with external data,
  such as a request parameters, you can use `Ecto.Changeset.cast/3`
  after `build_assoc/3`:

      parent
      |> Ecto.build_assoc(:child)
      |> Ecto.Changeset.cast(params, [:field1, :field2])

  """
  def build_assoc(%{__struct__: schema} = struct, assoc, attributes \\ %{}) do
    assoc = Ecto.Association.association_from_schema!(schema, assoc)
    assoc.__struct__.build(assoc, struct, drop_meta(attributes))
  end

  defp drop_meta(%{} = attrs), do: Map.drop(attrs, [:__struct__, :__meta__])
  defp drop_meta([_ | _] = attrs), do: Keyword.drop(attrs, [:__struct__, :__meta__])

  @doc """
  Builds a query for the association in the given struct or structs.

  ## Examples

  In the example below, we get all comments associated to the given
  post:

      post = Repo.get Post, 1
      Repo.all Ecto.assoc(post, :comments)

  `assoc/3` can also receive a list of posts, as long as the posts are
  not empty:

      posts = Repo.all from p in Post, where: is_nil(p.published_at)
      Repo.all Ecto.assoc(posts, :comments)

  This function can also be used to dynamically load through associations
  by giving it a list. For example, to get all authors for all comments for
  the given posts, do:

      posts = Repo.all from p in Post, where: is_nil(p.published_at)
      Repo.all Ecto.assoc(posts, [:comments, :author])

  ## Options

    * `:prefix` - the prefix to fetch assocs from. By default, queries
      will use the same prefix as the first struct in the given collection.
      This option allows the prefix to be changed.

  """
  def assoc(struct_or_structs, assocs, opts \\ []) do
    [assoc | assocs] = List.wrap(assocs)

    structs =
      case struct_or_structs do
        nil -> raise ArgumentError, "cannot retrieve association #{inspect(assoc)} for nil"
        [] -> raise ArgumentError, "cannot retrieve association #{inspect(assoc)} for empty list"
        struct_or_structs -> List.wrap(struct_or_structs)
      end

    sample = hd(structs)
    prefix = assoc_prefix(sample, opts)
    schema = sample.__struct__
    refl = %{owner_key: owner_key} = Ecto.Association.association_from_schema!(schema, assoc)

    values =
      Enum.uniq(
        for(
          struct <- structs,
          assert_struct!(schema, struct),
          key = Map.fetch!(struct, owner_key),
          do: key
        )
      )

    case assocs do
      [] ->
        %module{} = refl
        %{module.assoc_query(refl, nil, values) | prefix: prefix}

      assocs ->
        %{
          Ecto.Association.filter_through_chain(schema, [assoc | assocs], values)
          | prefix: prefix
        }
    end
  end

  defp assoc_prefix(sample, opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} ->
        prefix

      :error ->
        case sample do
          %{__meta__: %{prefix: prefix}} -> prefix
          # Must be an embedded schema
          _ -> nil
        end
    end
  end

  @doc """
  Checks if an association is loaded.

  ## Examples

      iex> post = Repo.get(Post, 1)
      iex> Ecto.assoc_loaded?(post.comments)
      false
      iex> post = post |> Repo.preload(:comments)
      iex> Ecto.assoc_loaded?(post.comments)
      true

  """
  def assoc_loaded?(%Ecto.Association.NotLoaded{}), do: false
  def assoc_loaded?(list) when is_list(list), do: true
  def assoc_loaded?(%_{}), do: true
  def assoc_loaded?(nil), do: true

  @doc """
  Resets fields in a struct to their default values.

  ## Examples

      iex> post = post |> Repo.preload(:author)
      %Post{title: "hello world", author: %Author{}}
      iex> Ecto.reset_fields(post, [:title, :author])
      %Post{
        title: "default title",
        author: #Ecto.Association.NotLoaded<association :author is not loaded>
      }

  """
  @spec reset_fields(Ecto.Schema.t(), list()) :: Ecto.Schema.t()
  def reset_fields(struct, []), do: struct

  def reset_fields(%{__struct__: schema} = struct, fields) do
    default_struct = schema.__struct__()
    default_fields = Map.take(default_struct, fields)
    Map.merge(struct, default_fields)
  end

  @doc """
  Gets the metadata from the given struct.
  """
  def get_meta(struct, :context),
    do: struct.__meta__.context

  def get_meta(struct, :state),
    do: struct.__meta__.state

  def get_meta(struct, :source),
    do: struct.__meta__.source

  def get_meta(struct, :prefix),
    do: struct.__meta__.prefix

  @doc """
  Returns a new struct with updated metadata.

  It is possible to set:

    * `:source` - changes the struct query source
    * `:prefix` - changes the struct query prefix
    * `:context` - changes the struct meta context
    * `:state` - changes the struct state

  Please refer to the `Ecto.Schema.Metadata` module for more information.
  """
  @spec put_meta(Ecto.Schema.schema(), meta) :: Ecto.Schema.schema()
        when meta: [
               source: Ecto.Schema.source(),
               prefix: Ecto.Schema.prefix(),
               context: Ecto.Schema.Metadata.context(),
               state: Ecto.Schema.Metadata.state()
             ]
  def put_meta(%{__meta__: meta} = struct, opts) do
    case put_or_noop_meta(opts, meta, false) do
      :noop -> struct
      meta -> %{struct | __meta__: meta}
    end
  end

  defp put_or_noop_meta([{key, value} | t], meta, updated?) do
    case meta do
      %{^key => ^value} -> put_or_noop_meta(t, meta, updated?)
      _ -> put_or_noop_meta(t, put_meta(meta, key, value), true)
    end
  end

  defp put_or_noop_meta([], meta, true), do: meta
  defp put_or_noop_meta([], _meta, false), do: :noop

  defp put_meta(meta, :state, state) do
    if state in [:built, :loaded, :deleted] do
      %{meta | state: state}
    else
      raise ArgumentError, "invalid state #{inspect(state)}"
    end
  end

  defp put_meta(meta, :source, source) do
    %{meta | source: source}
  end

  defp put_meta(meta, :prefix, prefix) do
    %{meta | prefix: prefix}
  end

  defp put_meta(meta, :context, context) do
    %{meta | context: context}
  end

  defp put_meta(_meta, key, _value) do
    raise ArgumentError, "unknown meta key #{inspect(key)}"
  end

  defp assert_struct!(module, %{__struct__: struct}) do
    if struct != module do
      raise ArgumentError,
            "expected a homogeneous list containing the same struct, " <>
              "got: #{inspect(module)} and #{inspect(struct)}"
    else
      true
    end
  end

  @doc """
  Loads previously dumped `data` in the given `format` into a schema.

  The first argument can be an embedded schema module, or a map (of types) and
  determines the return value: a struct or a map, respectively.

  The second argument `data` specifies fields and values that are to be loaded.
  It can be a map, a keyword list, or a `{fields, values}` tuple. Fields can be
  atoms or strings.

  The third argument `format` is the format the data has been dumped as. For
  example, databases may dump embedded to `:json`, this function allows such
  dumped data to be put back into the schemas.

  Fields that are not present in the schema (or `types` map) are ignored.
  If any of the values has invalid type, an error is raised.

  Note that if you want to load data into a non-embedded schema that was
  directly persisted into a given repository, then use `c:Ecto.Repo.load/2`.

  ## Examples

      iex> result = Ecto.Adapters.SQL.query!(MyRepo, "SELECT users.settings FROM users", [])
      iex> Enum.map(result.rows, fn [settings] -> Ecto.embedded_load(Setting, Jason.decode!(settings), :json) end)
      [%Setting{...}, ...]
  """
  @spec embedded_load(
          module_or_map :: module | map(),
          data :: map(),
          format :: atom()
        ) :: Ecto.Schema.t() | map()
  def embedded_load(schema_or_types, data, format) do
    Ecto.Schema.Loader.unsafe_load(
      schema_or_types,
      data,
      &Ecto.Type.embedded_load(&1, &2, format)
    )
  end

  @doc """
  Dumps the given struct defined by an embedded schema.

  This converts the given embedded schema to a map to be serialized
  with the given format. For example:

      iex> Ecto.embedded_dump(%Post{}, :json)
      %{title: "hello"}

  """
  @spec embedded_dump(Ecto.Schema.t(), format :: atom()) :: map()
  def embedded_dump(%schema{} = data, format) do
    Ecto.Schema.Loader.safe_dump(
      data,
      schema.__schema__(:dump),
      &Ecto.Type.embedded_dump(&1, &2, format)
    )
  end
end
