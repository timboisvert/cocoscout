# frozen_string_literal: true

# Who gets a day's tips when the clock decides (plan §9.14). The register
# day keeps its tips by quarter hour; Staffing says who was on then. Each
# quarter's tips go to the people on the bar at the time: a role that takes
# a fixed cut (Bar back, 15%) comes off the top first, split between its
# people on; the rest splits evenly between the equal-share people on. A
# quarter with no equal-share person on goes to the pool, which splits
# evenly between everyone in the rows at the end. A share someone typed
# stays as typed; the computed shares adjust around it so the rows still
# add up to the day's tips.
#
#   split = TipSplit.new(rule:, tips_cents:, tips_by_time:, workers:, shares:)
#   split.applies?   # the rule is on and the clock has something to read
#   split.rows       # one Row per person: span, cents, how
#   split.pool       # what rang up with nobody on
class TipSplit
  Span = Data.define(:from, :to, :house_role_id) do
    def hours = ((to - from) / 1.hour).round(2)
    def covers?(start, finish) = from < finish && to > start
  end

  Pool = Data.define(:cents, :orders)

  Row = Data.define(:person, :staff_member, :house_role, :spans, :cents, :source, :method, :share, :on_cents, :on_orders, :cut_cents, :pool_cents, :percent) do
    def typed? = source == "typed"
    def locked? = share&.payout_contribution_id.present?
    def worked_from = spans.map(&:from).min
    def worked_to = spans.map(&:to).max
    def hours = spans.sum(&:hours).round(2)
    def span_words
      return nil if spans.empty?

      "#{TipSplit.clock(worked_from)} to #{TipSplit.clock(worked_to)}"
    end

    # The line under the name: where this share came from.
    def how
      return "Typed in." if typed?

      parts = []
      parts << "#{TipSplit.percent_words(percent)} off the top while on" if cut_cents.positive?
      parts << "from #{on_orders} #{'order'.pluralize(on_orders)} while on" if on_cents.positive? || (on_orders.positive? && cut_cents.zero?)
      parts << "#{TipSplit.money(pool_cents)} from the pool" if pool_cents.positive?
      return "Nothing rang up while on." if parts.empty?

      "#{parts.join(', plus ').sub(/\A./, &:upcase)}."
    end
  end

  def self.money(cents) = ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  def self.clock(time) = time.in_time_zone.strftime("%-l:%M %P").sub(":00", "")
  def self.percent_words(percent) = "#{percent % 1 == 0 ? percent.to_i : percent}%"

  # rule          the organization's TipRule (nil = off)
  # tips_cents    the day's tips, from the registers
  # tips_by_time  { quarter iso8601 => { "cents" =>, "orders" => } }, the registers' merged
  # workers       SettleUp::Workers, each with spans (from Staffing or a saved share)
  # shares        the day's saved TipShares
  def initialize(rule:, tips_cents:, tips_by_time:, workers:, shares:, roles_by_id: nil)
    @rule = rule
    @tips_cents = tips_cents.to_i
    @tips_by_time = tips_by_time || {}
    @workers = workers
    @shares = shares.index_by(&:person_id)
    @roles_by_id = roles_by_id || HouseRole.where(id: (workers.flat_map { |w| w.spans.map(&:house_role_id) } + shares.map(&:house_role_id)).compact.uniq).index_by(&:id)
  end

  def applies?
    @rule&.enabled? == true && timed_cents.positive? && sharers.any?
  end

  def rows
    @rows ||= compute
  end

  def pool
    rows
    @pool
  end

  private

  def timed_cents = @tips_by_time.values.sum { |q| q["cents"].to_i }

  # The people in the rows: anyone on in a role that shares, plus anyone
  # already given a share (typed, or added by hand with a span).
  def sharers
    @sharers ||= @workers.select do |worker|
      share = @shares[worker.person.id]
      share.present? || worker.spans.any? { |span| @rule.shares?(span.house_role_id) }
    end
  end

  def compute
    tally = Hash.new { |h, k| h[k] = { on_cents: 0.0, on_orders: 0, cut_cents: 0.0, pool_cents: 0.0, percent: 0.0 } }
    pool_cents = 0.0
    pool_orders = 0

    @tips_by_time.each do |key, quarter|
      cents = quarter["cents"].to_i
      orders = quarter["orders"].to_i
      next if cents.zero? && orders.zero?

      start = Time.iso8601(key)
      finish = start + 15.minutes
      on = sharers.filter_map do |worker|
        span = worker.spans.find { |sp| sp.covers?(start, finish) && @rule.shares?(sp.house_role_id) }
        [ worker, span.house_role_id ] if span
      end
      if on.empty?
        pool_cents += cents
        pool_orders += orders
        next
      end

      remaining = cents.to_f
      on.group_by(&:last).each do |role_id, people|
        next unless @rule.kind_for(role_id) == "percent"

        cut = cents * @rule.percent_for(role_id) / 100.0
        remaining -= cut
        people.each do |worker, _|
          tally[worker.person.id][:cut_cents] += cut / people.size
          tally[worker.person.id][:percent] = @rule.percent_for(role_id)
          tally[worker.person.id][:on_orders] += orders
        end
      end
      equal = on.select { |_, role_id| @rule.kind_for(role_id) == "equal" }
      if equal.empty?
        pool_cents += remaining
      else
        equal.each do |worker, _|
          tally[worker.person.id][:on_cents] += remaining / equal.size
          tally[worker.person.id][:on_orders] += orders
        end
      end
    end
    # Tips the registers counted that have no time (an older day): the pool.
    pool_cents += [ @tips_cents - timed_cents, 0 ].max
    @pool = Pool.new(cents: pool_cents.round, orders: pool_orders)

    typed = sharers.select { |w| frozen?(@shares[w.person.id]) }
    computed = sharers - typed
    computed.each { |w| tally[w.person.id][:pool_cents] += pool_cents / computed.size } if computed.any?

    typed_total = typed.sum { |w| @shares[w.person.id].amount_cents }
    available = [ @tips_cents - typed_total, 0 ].max
    raw = computed.to_h { |w| t = tally[w.person.id]; [ w.person.id, t[:on_cents] + t[:cut_cents] + t[:pool_cents] ] }
    raw_total = raw.values.sum
    scaled = if raw_total.positive? then raw.transform_values { |v| v * available / raw_total }
    elsif computed.any? then raw.transform_values { available.to_f / computed.size }
    else {}
    end
    amounts = largest_remainder(scaled, available)

    sharers.sort_by { |w| [ w.spans.any? ? 0 : 1, w.spans.map(&:from).min || Time.at(0), w.person.name.to_s ] }.map do |worker|
      share = @shares[worker.person.id]
      t = tally[worker.person.id]
      role_id = share&.house_role_id || worker.spans.first&.house_role_id
      frozen = frozen?(share)
      Row.new(person: worker.person, staff_member: worker.staff_member, house_role: @roles_by_id[role_id], spans: worker.spans,
              cents: frozen ? share.amount_cents : amounts.fetch(worker.person.id, 0), source: frozen ? "typed" : "computed",
              method: share&.method || (worker.staff_member ? "payout" : "cash"), share: share,
              on_cents: t[:on_cents].round, on_orders: t[:on_orders], cut_cents: t[:cut_cents].round, pool_cents: t[:pool_cents].round, percent: t[:percent])
    end
  end

  # A typed share stays as typed; one already on a payout run can't move.
  def frozen?(share) = share.present? && (share.source == "typed" || share.payout_contribution_id.present?)

  # Whole cents that add up to the total, the leftovers to the biggest remainders.
  def largest_remainder(floats, total)
    floors = floats.transform_values(&:floor)
    short = total - floors.values.sum
    floats.sort_by { |id, v| [ -(v - v.floor), id ] }.first([ short, 0 ].max).each { |id, _| floors[id] += 1 }
    floors
  end
end
