# frozen_string_literal: true

module QueryCounter
  # Counts real SQL statements issued during the block, ignoring schema
  # introspection and transaction control statements so the count reflects
  # only the queries the code under test actually issues.
  def count_queries(&block)
    count = 0
    ignored_names = %w[SCHEMA TRANSACTION]

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless ignored_names.include?(payload[:name])
    end

    block.call
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
