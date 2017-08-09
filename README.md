## `refurb`

Refurb is a library for building PostgreSQL database migration software. Over the course of developing a database-backed software product in a team, you'll want to make organized updates to the database's schema and data that can be automatically reproduced in other environments. Refurb implements this process for Haskell projects in a fairly straightforward way, where individual changes to the database are applied in order by Haskell actions you make and check in with your code as usual.

### Quick tour

`refurb` is a library whose primary public interface is `Refurb.refurbMain` and is intended to implement a command-line tool, much like `Setup.hs` uses `defaultMain` from Cabal (the library) to implement the build system or `test/Main.hs` might use `hspec`. You pass a list of `Migration`s to `refurbMain` along with a way to obtain the database connection parameters, and the library will take care of creating and maintaining an in-database list of applied migrations and providing a CLI for users to apply migrations, query applied migrations, and make backups.

A `Migration` is a small structure with:

* What PostgreSQL schema to apply the migration to. All migrations are qualified by the schema they apply to and schemas are automatically created by Refurb if they don't already exist.
* A key to identify the migration within the schema, for example `create-first-table`.
* An execution action of the type `MonadMigration m => m ()` which is invoked to apply the actual change, e.g. issue some `create table` statements.
* An optional check action of the type `MonadMigration m => Maybe (m ())` which is invokved prior to the execution action to check preconditions. It can signal errors (much as the execution action can) to abort the migration from being executed and is present purely to help you organize your code. It's run just like the execution action is, if present.

A working example is located in the `example/` directory. It's not a complete worked example project, as in a normal project you'd have your own product code as well as the migration related code presented in the example.

### Using refurb in your project

While `example/` contains a working example of refurb, it doesn't reflect totally how you might use it in your own project. Project organization is in the end up to you and who you work with of course, but here's how we arrange our projects with Refurb:

* `package.yaml` - [hpack](https://github.com/sol/hpack) file which generates `myawesomeserver.cabal`. If you're not familiar with hpack, it's not required. It's just a nicer way to generate cabal files than by hand.
* `myawesomeserver.cabal` - generated by hpack and contains:
   * A library section with sources in `src/` (`hs-source-dirs: src` in cabal terms). `src` contains all the primary code of your product.
   * An executable section `myawesomeserver-exe` with sources in `app/server/` that depends on the `myawesomeserver` library. This executable launches your main product (presumably a server). This launch expects that the database has already been migrated and doesn't use refurb directly.
   * An executable section `myawesomeserver-refurb` with sources in `app/refurb/` that depends on the `myawesomeserver` and `refurb` libraries. This executable runs refurb for your project.
   * One or more other test suites or executable sections. At Confer, we have another executable which makes starting and stopping a development environment with PostgreSQL easy, for example.
* `app/server/Main.hs` - main entry point to your server. Usually just calls something in the `myawesomeserver` library.
* `app/refurb/Main.hs` - entry point for refurb. Usually just calls `refurbMain` with your list of migrations. Those migrations could be in `app/refurb/` or in your main `src/`.
* `src/` - directory with your main product source files.

With this arrangement a build produces both `myawesomeserver-exe` and `myawesomeserver-refurb`. Make sure to run `myawesomeserver-refurb migrate --execute` before running `myawesomeserver-exe` so the database gets migrated before the server tries to start.

### Invoking a refurb executable

`refurb` implements a CLI to query what migrations have been applied to a database, query what would happen prior to actually migrating, and migrating. It's broken into several subcommands which perform different maintenance functions. There are also a few top-level switches:

```
Available options:
  -h,--help                Show this help text
  -d,--debug               Turn on debug diagnostic logging
  --no-color               disable ANSI colorization
  -c,--config SERVER-CONFIG
                           Path to server config file to read database
                           connection information from
```

* `-h` / `--help` shows that help output.
* `-d` / `--debug` turns on extra execution logging. Note that all log messages produced by a migration action are always captured, even with this switch off. This merely controls the console output.
* `--no-color` suppresses ANSI colorization, e.g. for CI builds.
* `-c` / `--config` tells `refurb` where to find the server's config file. `refurb` itself doesn't care about the file contents, it just passes the config file path off to the function given to `refurbMain` to get the database connection information back.

#### `show-log`

`myawesomeserver-refurb -c configfile show-log` shows a complete list of migrations known about and applied to the database. It displays a table similar to the following though with glorious ANSI coloration unless you suppress it with `--no-color`:

```
ID     Timestamp           Duration        Result  Key
1      2017-04-03 15:27:17 5 milliseconds  success example.create-first-table
       not applied                                 example.populate-first-table (seed data)
```

Each column is probably self-explanatory, but:

* `ID` is the primary key in the `refurb.migration-log`. If this column is populated, it means that the corresponding migration was applied at some point for better or worse.
* `Timestamp` is the time and date (in UTC) when the migration was applied to the database. Shows `not applied` if the migration hasn't been applied.
* `Duration` is how long the migration took to execute when it was applied. If empty, it means the migration hasn't been applied.
* `Result` indicates whether the migration application succeeded or failed. If empty, it means the migration hasn't been applied.
* `Key` shows the qualified (that is, with schema) key of the migration along with a parenthetical note for seed data migrations.

#### `show-migration`

`myawesomeserver-refurb -c configfile show-migration example.create-first-table` shows the status of and log from the application of `example.create-first-table`. Naturally, if the migration has never been applied then no log will be available.

For example:

```
ID     Timestamp           Duration        Result  Key
1      2017-04-03 15:27:17 5 milliseconds  success example.create-first-table

2017-04-03 15:27:17.780579 [LevelDebug] create sequence first_table_seq @(refurb-0.2.0.0-eWyEcrirqVIapweij3svH:Refurb.MigrationUtils src/Refurb/MigrationUtils.hs:98:3)
2017-04-03 15:27:17.782271 [LevelDebug] create table first_table (id int not null primary key default nextval('first_table_seq'), t text not null) @(refurb-0.2.0.0-eWyEcrirqVIapweij3svH:Refurb.MigrationUtils src/Refurb/MigrationUtils.hs:98:3)
```

### `backup`

`myawesomeserver-refurb -c configfile backup path/to/backupfile` creates a compressed binary database backup using `pg_dump` which can be restored with `pg_restore`. You can also trigger a backup automatically before migration with the `-b path/to/backupfile` switch to `migrate`.

### `migrate`

`myawesomeserver-refurb -c configfile migrate` is the main purpose of `refurb` - applying migrations to a database. If given no additional options it will consult the database and known migration list and display a list of migrations that would be executed. As a safety measure those migrations do not actually get executed unless you confirm that you want your database altered with `-e` / `--execute`.

By default the list of migrations to apply will be only the schema migrations and not seed data migrations (see next section for more); in a development or QA environment where you want seed data, pass `-s` / `--seed` to see what migrations including seed data migrations would be applied and pass `-s -e` / `--seed --execute` to actually apply them.

You can additionally request that the database be backed up prior to migration using `-b` / `--backup` and passing the path where you want the backup file created.

### Migration types

Migrations come in two flavors: `schemaMigration` and `seedDataMigration`. The former type are run everywhere, while the second type are only run when requested with `--seed` and the `refurb.config` table doesn't have the `prod_system` flag set. The two types are intended to help with a common workflow, where in development and QA environments it's helpful to have seed data installed in your database, e.g. test users and configuration. Conversely seed data should never make its way into production, especially when installing that seed data might be destructive.

Other than when they run, both types are equivalent in functionality.

As an extra check to make it hard to accidentally apply seed data migrations to production systems, `refurb` will flatly refuse to run any seed data migrations when the `prod_system` boolean is true in `refurb.config`. It's not possible to set this boolean via the `refurb` CLI, so just `update refurb.config set prod_system = 't'` to set it.

### Migration actions

Migration actions are Haskell actions of the type `MonadMigration m => m ()`. `MonadMigration` is defined this way (with `ConstraintKinds`):

```haskell
type MonadMigration m =
  ( MonadBaseControl IO m       -- access to underlying IO
  , MonadMask m                 -- can use bracket and friends
  , MonadReader PG.Connection m -- can ask for a connection to the DB
  , MonadLogger m               -- can log using monad-logger
  )
```

The database connection is of type `PG.Connection` with `PG` being `Database.PostgreSQL.Simple` from [`postgresql-simple`](https://github.com/lpsmith/postgresql-simple). So at its most basic a migration action could use that connection straightforwardly:

```haskell
executeMyMigration :: MonadMigration m => m ()
executeMyMigration = do
  conn <- ask
  rowsAffected <- PG.execute_ conn "create table foo (bar text)"
  $logInfo "created foo!"
  pure ()
```

Though this can be simplified as `refurb` provides several shorthands and utilities for writing migrations. They're located in the `Refurb.MigrationUtils` module and re-exported by `Refurb`. The previous example could be shortened to:

```haskell
executeMyMigration :: MonadMigration m => m ()
executeMyMigration =
  void $ execute_ "create table foo (bar text)"
```

`execute_` being a helper which asks for the database connection and runs some query against it, logging that query at debug level.

#### Migration action helpers

These helpers are all located in `Refurb.MigrationUtils`, so go there for more details.

* `execute` / `execute_` executes a single SQL statement which doesn't produce table output. The `_` version takes a literal query, while the non-`_` version takes a parameterized query along with parameters to substitute in. See `qqSql` below for a helper quasiquote which makes embedding a multiline SQL statement more pleasant.
* `executeMany` / `executeSeries_` execute a series of SQL statements which don't produce table output. The `_` version takes a literal query, while the non-`_` version takes a parameterized query along with parameters to substitute in. See `qqSqls` below for a helper quasiquote which makes embedding multiple statement SQL scripts more pleasant.
* `query` / `query_` executes a SQL query and return the results as a list using `postgresql-simple`'s `FromRow` machinery. The `_` version takes a literal query, while the non-`_` version takes a parameterized query along with parameters to substitute in.
* `runQuery` executes an [Opaleye](https://github.com/tomjaguarpaw/haskell-opaleye) `Query`. `refurb` internally uses Opaleye to manage its storage tables, so this comes at no extra cost in dependency terms.
* `runInsertMany` inserts a series of rows into a table using Opaleye.
* `runUpdate` updates rows in a table using Opaleye.
* `runDelete` deletes rows from a table using Opaleye.
* `doesSchemaExist` checks if a schema exists or not using `information_schema`. Note that this is not typically required as `refurb` automatically creates schemas for you if they don't already exist.
* `doesTableExist` check if a table exists or not in a given schema using `information_schema`.

#### SQL embedding quasiquotes

Writing SQL as string literals can get very tedious as Haskell doesn't have a separate multiline string literal syntax and instead relies on `\` to elide the newlines. To make embedding SQL queries in code easier, `refurb` provides two quasiquotes: `qqSql` and `qqSqls`.

`qqSql` is essentially a multiline string literal and `[qqSql|foo|]` is equivalent to `"foo" :: PG.Query`.

`qqSqls` is more complicated and intended for use with `executeSeries_`. It implements a simplistic version of the `;` delimited syntax common in SQL REPLs and yields a `[Query]`.

For example:

```haskell
queries :: [PG.Query]
queries =
  [qqSqls|
    create sequence stuff_seq;
    create table stuff
      ( id bigint not null primary key default nextval('stuff_seq')
      );
    |]
```

is equivalent to:

```haskell
queries =
  [ "create sequence stuff_seq\n"
  , "create table stuff\n( id bigint not null primary key default nextval('stuff_seq')\n)\n"
  ]
```

As mentioned, it only implements a simplistic `;` delimited syntax. It separates statements whenever a `;` occurs at the beginning or end of line after stripping whitespace. Thus if you have a literal `;` don't put it at beginning or end of line, and conversely don't have more than one statement per line.

### Migration logs and output

Migrations usually produce log entries as they execute, e.g. with the DDL statements they execute. This output is copied to the console output as the migrations run if the log message is at info or higher, or if `-d` / `--debug` is given when running `migrate --execute`. This output (including debug messages) is also captured and stored in the `refurb.migration_log` table for later perusal using `show-migration`.

### Failed migrations

Presently if a migration fails refurb will store a record of it along with the logs from the failing migration and will never try to apply that migration again because there's no general safe way to untangle what the migration might have done before it failed. The intended pattern is that if a migration fails, you figure out what went wrong and untangle it and then either update the existing `refurb.migration_log` to be marked successful, or remove the record and rerun the migration.

Failure of a migration is currently done by using either `fail` or throwing an exception from the migration execution or check action.

Future improvements to the handling of failed migrations might be implemented, and suggestions are welcome.

### `refurb` schema

Refurb maintains its own schema to keep track of applied migrations, both for informational purposes and to determine which known migrations (i.e. those given to `refurbMain`) have not yet been applied and need execution.

The `refurb` schema contains two tables: `migration_log` and `config`. `migration_log` contains a record for each migration applied.

`config` has only one column presently, `prod_system`. `prod_system` is a boolean whose only effect is to disable the application of seed data migrations (when `t`rue).

`migration_log` has several columns:

* `id` - primary key, serially assigned.
* `qualified_key` - the migration's key qualified by its schema in `schema.key` form, e.g. `example.create-first-table`.
* `applied` - timestamp when the migration was applied.
* `output` - the log output of the migration application.
* `result` - either `success` or `failure`.
* `duration` - number of (fractional) seconds the migration took to execute.

### Long term maintenance

One issue with using Haskell migration actions is that over time the migrations for a previous version might use types which no longer exist or have different definitions and thus not compile or do the wrong thing. It's up to you to decide what works best for your project. If you use mostly `execute` style migrations with embedded SQL there might not be a problem. Alternatively, you could keep old versions of data structures around for migrations to use, or comment out old migrations between releases and rely on running previous releases' migrations.

Suggestions and contributions welcome to assist with various strategies here.

## Maturity

As of writing, we use this library in our Haskell project which employs a database and have had no major issues. We have not yet released to production and have not gone through a series of releases, so improvements in the long term use might still be due.  We'd appreciate any fixes, improvements, or experience reports.

## Contributing

Contributions and feedback welcome! File and issue or make a PR.

## Chat

Asa (@asa) and Ross (@dridus) lurk on [fpchat](https://fpchat.com). You can also reach us at `oss@confer.health`.

