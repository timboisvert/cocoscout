# frozen_string_literal: true

# N+1 detection you opt into, one example at a time.
#
# Prosopite is inert unless scan/finish bracket the code, so `raise = true` in
# the test initializer costs nothing globally — only a spec that opts in can
# fail on it. That's deliberate: the app still has a long tail of N+1s, and a
# suite that fails on all of them today would block every unrelated change.
# Paths get locked down as they're fixed.
#
# Two forms, because request specs and service specs want different things:
#
#   it "renders the week", :no_n_plus_one do        # whole example, setup included
#     get manage_staffing_scheduling_path
#   end
#
#   expect { service.call }.not_to have_n_plus_one_queries   # exercise phase only
#
# The tag wraps the group's before/let! hooks too, which is what
# `allow_stack_paths` (spec/factories, factory_bot) exists to neutralise —
# Prosopite attributes each group of identical queries to its cleaned caller
# stack, so factory inserts don't read as the app's N+1.
#
# Never nest the two: Prosopite's scan is per-thread and not re-entrant.
module NPlusOne
  # Collects Prosopite's warnings instead of raising, so a matcher can report
  # them. Returns the messages ([] when clean).
  class Collector
    attr_reader :messages

    def initialize = @messages = []
    def warn(message) = @messages << message.to_s
  end

  # Prosopite exposes these as attr_writer only — there's no `Prosopite.raise`
  # reader (it would collide with Kernel#raise), so save and restore the ivars
  # rather than hardcoding the initializer's values in a second place.
  SWAPPED = %i[@raise @custom_logger @rails_logger].freeze

  def capture_n_plus_ones
    collector = Collector.new
    previous = SWAPPED.map { |ivar| Prosopite.instance_variable_get(ivar) }
    Prosopite.raise = false
    Prosopite.custom_logger = collector
    Prosopite.rails_logger = false

    Prosopite.scan
    yield
    # finish is what reports, so it has to run before we restore the globals.
    Prosopite.finish
    collector.messages
  ensure
    SWAPPED.each_with_index { |ivar, i| Prosopite.instance_variable_set(ivar, previous[i]) }
  end
end

RSpec.configure do |config|
  config.include NPlusOne

  config.around(:each, :no_n_plus_one) do |example|
    Prosopite.scan
    example.run
    Prosopite.finish
  end
end

RSpec::Matchers.define :have_n_plus_one_queries do
  supports_block_expectations

  match do |block|
    @warnings = capture_n_plus_ones(&block)
    @warnings.any?
  end

  failure_message { "expected an N+1 query, but none was detected" }
  failure_message_when_negated { "expected no N+1 queries, got:\n\n#{@warnings.join("\n\n")}" }
end
