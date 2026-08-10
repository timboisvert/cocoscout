# frozen_string_literal: true

# Counts the SQL a block issues, so a spec can assert the *shape* of a query
# load rather than a magic number.
#
# The useful assertion is almost always slope, not absolute count: build one of
# a thing, measure; build fifteen, measure again; assert the difference is
# small. An absolute budget is brittle (any unrelated preload moves it), but the
# slope only moves when someone reintroduces a per-record loop — which is the
# thing that actually regresses.
#
#   baseline = count_queries { subject.call }
#   14.times { make_another_one }
#   expect(count_queries { subject.call } - baseline).to be <= 3
#
# Use `captured_queries` instead when a slope assertion fails and you need to
# see which query multiplied.
module QueryCounting
  def count_queries(&block)
    captured_queries(&block).size
  end

  def captured_queries
    queries = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      # Cached hits aren't round trips, and schema/transaction chatter isn't the
      # app's doing — counting either makes slopes noisy for no signal.
      next if payload[:cached]
      next if payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)

      queries << payload[:sql]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end
end

RSpec.configure do |config|
  config.include QueryCounting
end
