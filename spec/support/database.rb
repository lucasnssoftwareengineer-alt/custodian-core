# frozen_string_literal: true

require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Migration.verbose = false

Dir[File.expand_path("../../db/migrate/*.rb", __dir__)].each { |f| require f }

ActiveRecord::MigrationContext.new(
  File.expand_path("../../db/migrate", __dir__)
).migrate

# Test-only schema for a throwaway host app model, used to prove that
# Node#subject works with an arbitrary ActiveRecord class, not just Node itself.
ActiveRecord::Schema.define do
  create_table :dummy_host_objects, force: true
end
