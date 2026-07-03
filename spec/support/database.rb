# frozen_string_literal: true

require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Migration.verbose = false

Dir[File.expand_path("../../db/migrate/*.rb", __dir__)].sort.each { |f| require f }

ActiveRecord::MigrationContext.new(
  File.expand_path("../../db/migrate", __dir__)
).migrate
